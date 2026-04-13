from fastapi import FastAPI
from pydantic import BaseModel
from typing import List, Dict
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import logging

logger = logging.getLogger(__name__)
app = FastAPI(title="Garden Pricing Engine")

# ─────────────────────────────────────────────
#  Modelos de entrada / salida
# ─────────────────────────────────────────────

class BookingRecord(BaseModel):
    date: str        # YYYY-MM-DD
    count: int
    revenue: float
    price: float = 0.0   # precio cobrado ese día (para elasticidad)

class AnalyzeRequest(BaseModel):
    service_type: str          # PASEO | HOSPEDAJE
    history: List[BookingRecord]
    precio_actual: float
    precio_promedio_zona: float
    precio_min_zona: float
    precio_max_zona: float
    forecast_days: int = 7

class PricingAnalysis(BaseModel):
    # — Demanda —
    demanda_forecast_7d: float
    demanda_forecast_30d: float
    tendencia: str                  # rising | stable | falling
    fuerza_tendencia: float         # 0–1

    # — Optimización de precio (pura matemática) —
    precio_optimo_matematico: int
    elasticidad_precio: float       # ej: -1.2 → caída de 1.2% demanda por cada +1% precio
    ingreso_proyectado_actual: float
    ingreso_proyectado_optimo: float
    mejora_ingreso_pct: float
    rango_precio_seguro: Dict[str, int]   # { min, max }

    # — Estacionalidad —
    factor_estacional_actual: float        # 1.0 = normal, 1.2 = +20% sobre promedio
    dias_peak_proximos_7: List[str]
    dias_slow_proximos_7: List[str]
    patron_semanal: Dict[str, float]       # { "lunes": 0.7, ..., "domingo": 1.2 }

    # — Historial —
    reservas_7d: int
    reservas_30d: int
    reservas_90d: int
    variacion_vs_mes_anterior_pct: float
    dias_sin_reserva: int
    ingreso_promedio_por_reserva: float

    # — Posición en mercado —
    percentil_precio_zona: float           # 0–100
    precio_vs_promedio_zona_pct: float     # % sobre/bajo promedio

    # — Metadata —
    modelo_usado: str
    confianza: str                  # alta | media | baja
    puntos_de_datos: int


# ─────────────────────────────────────────────
#  Endpoint principal
# ─────────────────────────────────────────────

@app.post("/analyze", response_model=PricingAnalysis)
async def analyze(req: AnalyzeRequest):
    try:
        return _run_full_analysis(req)
    except Exception as e:
        logger.error(f"[analyze] Error: {e}", exc_info=True)
        return _fallback_analysis(req)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "garden-pricing-engine"}


# ─────────────────────────────────────────────
#  Motor de análisis completo
# ─────────────────────────────────────────────

def _run_full_analysis(req: AnalyzeRequest) -> PricingAnalysis:
    history = req.history
    n = len(history)

    # ── 1. Preparar serie temporal ──────────────────────────────────
    if n > 0:
        df = pd.DataFrame([{
            "ds": datetime.strptime(r.date, "%Y-%m-%d"),
            "y": r.count,
            "revenue": r.revenue,
            "price": r.price if r.price > 0 else req.precio_actual,
        } for r in history])
        df = df.set_index("ds").resample("D").agg({
            "y": "sum", "revenue": "sum", "price": "mean"
        }).fillna(0).reset_index()
        df["price"] = df["price"].replace(0, req.precio_actual)
    else:
        df = pd.DataFrame(columns=["ds", "y", "revenue", "price"])

    # ── 2. Demanda forecast ─────────────────────────────────────────
    demand_7d, demand_30d, trend, trend_strength, modelo, confianza = (
        _forecast_demand(df, req)
    )

    # ── 3. Elasticidad y precio óptimo ─────────────────────────────
    elasticidad = _estimate_elasticity(df, req.service_type)
    precio_optimo, ingreso_actual, ingreso_optimo, mejora_pct = (
        _optimize_price(req.precio_actual, demand_7d, elasticidad,
                        req.precio_min_zona, req.precio_max_zona)
    )

    # ── 4. Estacionalidad ───────────────────────────────────────────
    patron_semanal = _weekly_pattern(df)
    factor_estacional = _current_seasonal_factor(patron_semanal)
    dias_peak, dias_slow = _classify_next_days(patron_semanal, req.forecast_days)

    # ── 5. Historial ────────────────────────────────────────────────
    hoy = datetime.now()
    reservas_7d  = int(df[df["ds"] >= hoy - timedelta(days=7)]["y"].sum())
    reservas_30d = int(df[df["ds"] >= hoy - timedelta(days=30)]["y"].sum())
    reservas_90d = int(df[df["ds"] >= hoy - timedelta(days=90)]["y"].sum())

    # Variación vs mes anterior
    reservas_mes_ant = int(
        df[(df["ds"] >= hoy - timedelta(days=60)) &
           (df["ds"] < hoy - timedelta(days=30))]["y"].sum()
    )
    variacion_pct = (
        ((reservas_30d - reservas_mes_ant) / max(1, reservas_mes_ant)) * 100
        if reservas_mes_ant > 0 else 0.0
    )

    # Días sin reserva
    df_with_bookings = df[df["y"] > 0]
    dias_sin_reserva = (
        int((hoy - df_with_bookings["ds"].max()).days)
        if not df_with_bookings.empty else 30
    )

    ingreso_por_reserva = (
        float(df[df["y"] > 0]["revenue"].mean())
        if not df[df["y"] > 0].empty else req.precio_actual
    )

    # ── 6. Posición en mercado ──────────────────────────────────────
    percentil = _price_percentile(
        req.precio_actual, req.precio_min_zona, req.precio_max_zona
    )
    vs_promedio_pct = (
        ((req.precio_actual - req.precio_promedio_zona) /
         max(1, req.precio_promedio_zona)) * 100
    )

    # ── 7. Rango seguro de precio ───────────────────────────────────
    rango = {
        "min": max(int(req.precio_min_zona), int(req.precio_actual * 0.85)),
        "max": min(int(req.precio_max_zona), int(req.precio_actual * 1.20)),
    }

    return PricingAnalysis(
        demanda_forecast_7d=round(demand_7d, 2),
        demanda_forecast_30d=round(demand_30d, 2),
        tendencia=trend,
        fuerza_tendencia=round(trend_strength, 2),
        precio_optimo_matematico=precio_optimo,
        elasticidad_precio=round(elasticidad, 2),
        ingreso_proyectado_actual=round(ingreso_actual, 2),
        ingreso_proyectado_optimo=round(ingreso_optimo, 2),
        mejora_ingreso_pct=round(mejora_pct, 1),
        rango_precio_seguro=rango,
        factor_estacional_actual=round(factor_estacional, 2),
        dias_peak_proximos_7=dias_peak,
        dias_slow_proximos_7=dias_slow,
        patron_semanal=patron_semanal,
        reservas_7d=reservas_7d,
        reservas_30d=reservas_30d,
        reservas_90d=reservas_90d,
        variacion_vs_mes_anterior_pct=round(variacion_pct, 1),
        dias_sin_reserva=dias_sin_reserva,
        ingreso_promedio_por_reserva=round(ingreso_por_reserva, 2),
        percentil_precio_zona=round(percentil, 1),
        precio_vs_promedio_zona_pct=round(vs_promedio_pct, 1),
        modelo_usado=modelo,
        confianza=confianza,
        puntos_de_datos=len(df),
    )


# ─────────────────────────────────────────────
#  Módulos matemáticos independientes
# ─────────────────────────────────────────────

def _forecast_demand(df: pd.DataFrame, req: AnalyzeRequest):
    """Elige el mejor modelo según la cantidad de datos disponibles."""
    n = len(df[df["y"] > 0])

    if n < 5:
        return _rules_forecast(req)

    if n < 30:
        return _arima_forecast(df, req)

    return _prophet_forecast(df, req)


def _rules_forecast(req: AnalyzeRequest):
    today = datetime.now()
    dow = today.weekday()
    month = today.month

    dow_factors   = {0:0.70, 1:0.70, 2:0.75, 3:0.80, 4:1.10, 5:1.30, 6:1.20}
    month_factors = {1:1.20, 2:0.90, 3:0.85, 4:0.85, 5:0.90, 6:0.95,
                     7:1.15, 8:1.10, 9:0.90, 10:0.90, 11:0.95, 12:1.20}

    base = 3.0 if req.service_type == "PASEO" else 1.5
    f = dow_factors.get(dow, 1.0) * month_factors.get(month, 1.0)
    d7  = base * f
    d30 = base * month_factors.get(month, 1.0)
    trend = "rising" if f > 1.05 else ("falling" if f < 0.85 else "stable")
    return d7, d30, trend, abs(f - 1.0), "reglas", "baja"


def _arima_forecast(df: pd.DataFrame, req: AnalyzeRequest):
    try:
        from statsmodels.tsa.arima.model import ARIMA
        series = df.set_index("ds")["y"]
        model  = ARIMA(series, order=(1, 1, 1)).fit()

        f7  = max(0.0, float(model.forecast(steps=7).mean()))
        f30 = max(0.0, float(model.forecast(steps=30).mean()))

        counts = df["y"].values
        mid = len(counts) // 2
        slope = np.mean(counts[mid:]) - np.mean(counts[:mid])
        trend = "rising" if slope > 0.3 else ("falling" if slope < -0.3 else "stable")
        strength = min(1.0, abs(slope) / max(1.0, np.mean(counts)))

        return f7, f30, trend, round(strength, 2), "arima", "media"
    except Exception as e:
        logger.warning(f"ARIMA failed: {e}")
        return _rules_forecast(req)


def _prophet_forecast(df: pd.DataFrame, req: AnalyzeRequest):
    try:
        from prophet import Prophet

        train = df[["ds", "y"]].copy()
        # Feriados bolivianos como eventos especiales
        holidays = _bolivian_holidays_df()

        m = Prophet(
            yearly_seasonality=True,
            weekly_seasonality=True,
            daily_seasonality=False,
            holidays=holidays,
        )
        m.fit(train)

        fut7  = m.make_future_dataframe(periods=7)
        fut30 = m.make_future_dataframe(periods=30)
        fc7   = m.predict(fut7)
        fc30  = m.predict(fut30)

        d7  = max(0.0, float(fc7.tail(7)["yhat"].mean()))
        d30 = max(0.0, float(fc30.tail(30)["yhat"].mean()))

        # Tendencia y fuerza
        trend_slope = float(fc7["trend"].diff().tail(7).mean())
        trend = "rising" if trend_slope > 0.1 else ("falling" if trend_slope < -0.1 else "stable")
        strength = min(1.0, abs(trend_slope) / max(0.1, d7))

        # Confianza basada en intervalo
        last = fc7.tail(7).iloc[-1]
        interval = last["yhat_upper"] - last["yhat_lower"]
        conf = "alta" if interval < d7 * 0.5 else ("media" if interval < d7 else "baja")

        return d7, d30, trend, round(strength, 2), "prophet+arima", conf
    except Exception as e:
        logger.warning(f"Prophet failed: {e}")
        return _arima_forecast(df, req)


def _estimate_elasticity(df: pd.DataFrame, service_type: str) -> float:
    """
    Estima la elasticidad precio-demanda.
    Si hay variación de precios en el historial → regresión log-log.
    Si no → valores por defecto del sector (más elástico en paseo que hospedaje).
    """
    defaults = {"PASEO": -1.2, "HOSPEDAJE": -0.8}

    try:
        prices  = df["price"].values
        demands = df["y"].values

        # Necesitamos al menos 10 puntos con variación de precio > 5%
        price_range = prices.max() - prices.min() if len(prices) > 0 else 0
        if len(prices) < 10 or price_range < prices.mean() * 0.05:
            return defaults.get(service_type, -1.0)

        # Regresión log-log:  log(demand) = α + β·log(price)  → β = elasticidad
        mask = (prices > 0) & (demands > 0)
        if mask.sum() < 10:
            return defaults.get(service_type, -1.0)

        log_p = np.log(prices[mask])
        log_d = np.log(demands[mask])

        # Mínimos cuadrados
        A = np.vstack([np.ones_like(log_p), log_p]).T
        result = np.linalg.lstsq(A, log_d, rcond=None)
        beta = float(result[0][1])

        # Clampar a rango económicamente razonable [-2.5, -0.3]
        return float(np.clip(beta, -2.5, -0.3))

    except Exception:
        return defaults.get(service_type, -1.0)


def _optimize_price(
    precio_actual: float,
    demanda_7d: float,
    elasticidad: float,
    precio_min: float,
    precio_max: float,
) -> tuple:
    """
    Precio que maximiza ingresos usando D(p) = D0 · (p/p0)^e
    Revenue óptimo: p* = p0 · e/(e+1)  cuando e < -1 (demanda elástica)
    Para e > -1 (inelástica) → subir precio siempre aumenta ingresos (limitado por max)
    """
    if demanda_7d <= 0:
        return int(precio_actual), 0.0, 0.0, 0.0

    ingreso_actual = precio_actual * demanda_7d

    if elasticidad < -1:
        # Punto de máximo ingreso
        p_opt_raw = precio_actual * (elasticidad / (elasticidad + 1))
    else:
        # Demanda inelástica → subir precio hasta el máximo seguro
        p_opt_raw = precio_max

    # Respetar límites
    p_opt = float(np.clip(p_opt_raw, precio_min, precio_max))
    p_opt = round(p_opt)

    # Ingreso proyectado al precio óptimo
    demanda_optima = demanda_7d * ((p_opt / precio_actual) ** elasticidad)
    ingreso_optimo = p_opt * demanda_optima

    mejora_pct = ((ingreso_optimo - ingreso_actual) / max(1, ingreso_actual)) * 100

    return int(p_opt), round(ingreso_actual, 2), round(ingreso_optimo, 2), round(mejora_pct, 1)


def _weekly_pattern(df: pd.DataFrame) -> Dict[str, float]:
    """Patrón promedio de demanda por día de semana (normalizado → 1.0 = promedio)."""
    days_es = ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"]

    if df.empty or df["y"].sum() == 0:
        # Patrón por defecto: fines de semana son más altos
        return {d: v for d, v in zip(days_es,
                [0.70, 0.70, 0.75, 0.80, 1.10, 1.30, 1.20])}

    tmp = df.copy()
    tmp["dow"] = tmp["ds"].dt.dayofweek   # 0=lunes
    avg_by_dow = tmp.groupby("dow")["y"].mean()

    global_avg = avg_by_dow.mean()
    if global_avg == 0:
        return {d: 1.0 for d in days_es}

    pattern = {}
    for i, name in enumerate(days_es):
        val = avg_by_dow.get(i, global_avg)
        pattern[name] = round(float(val / global_avg), 2)

    return pattern


def _current_seasonal_factor(patron: Dict[str, float]) -> float:
    """Factor estacional para HOY."""
    days_es = ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"]
    dow = datetime.now().weekday()
    day_name = days_es[dow]
    return patron.get(day_name, 1.0)


def _classify_next_days(patron: Dict[str, float], n_days: int):
    """Clasifica los próximos n_days en peak vs slow según el patrón semanal."""
    days_es = ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"]
    peak, slow = [], []
    today = datetime.now()
    for i in range(1, n_days + 1):
        day = today + timedelta(days=i)
        name = days_es[day.weekday()]
        factor = patron.get(name, 1.0)
        label = day.strftime("%Y-%m-%d")
        if factor >= 1.15:
            peak.append(label)
        elif factor <= 0.80:
            slow.append(label)
    return peak, slow


def _price_percentile(precio: float, precio_min: float, precio_max: float) -> float:
    """Posición percentil del precio dentro del rango de la zona."""
    if precio_max <= precio_min:
        return 50.0
    return float(np.clip((precio - precio_min) / (precio_max - precio_min) * 100, 0, 100))


def _bolivian_holidays_df() -> pd.DataFrame:
    """DataFrame de feriados bolivianos para Prophet."""
    year = datetime.now().year
    raw = [
        (f"{year}-01-01", "Año Nuevo"),
        (f"{year}-01-22", "Día del Estado Plurinacional"),
        (f"{year}-05-01", "Día del Trabajo"),
        (f"{year}-05-27", "Día de la Madre"),
        (f"{year}-06-21", "Año Nuevo Andino"),
        (f"{year}-08-06", "Día de la Independencia"),
        (f"{year}-10-12", "Día de la Hispanidad"),
        (f"{year}-11-02", "Día de los Difuntos"),
        (f"{year}-12-25", "Navidad"),
    ]
    df = pd.DataFrame(raw, columns=["ds", "holiday"])
    df["ds"] = pd.to_datetime(df["ds"])
    return df


def _fallback_analysis(req: AnalyzeRequest) -> PricingAnalysis:
    """Análisis mínimo cuando todo falla."""
    d7, d30, trend, strength, modelo, conf = _rules_forecast(req)
    patron = _weekly_pattern(pd.DataFrame())
    peak, slow = _classify_next_days(patron, req.forecast_days)
    p_opt, ing_act, ing_opt, mejora = _optimize_price(
        req.precio_actual, d7, -1.0,
        req.precio_min_zona, req.precio_max_zona
    )
    percentil = _price_percentile(
        req.precio_actual, req.precio_min_zona, req.precio_max_zona
    )
    vs_avg = ((req.precio_actual - req.precio_promedio_zona) /
              max(1, req.precio_promedio_zona)) * 100

    return PricingAnalysis(
        demanda_forecast_7d=d7, demanda_forecast_30d=d30,
        tendencia=trend, fuerza_tendencia=strength,
        precio_optimo_matematico=p_opt,
        elasticidad_precio=-1.0,
        ingreso_proyectado_actual=ing_act,
        ingreso_proyectado_optimo=ing_opt,
        mejora_ingreso_pct=mejora,
        rango_precio_seguro={
            "min": max(int(req.precio_min_zona), int(req.precio_actual * 0.85)),
            "max": min(int(req.precio_max_zona), int(req.precio_actual * 1.20)),
        },
        factor_estacional_actual=_current_seasonal_factor(patron),
        dias_peak_proximos_7=peak,
        dias_slow_proximos_7=slow,
        patron_semanal=patron,
        reservas_7d=0, reservas_30d=0, reservas_90d=0,
        variacion_vs_mes_anterior_pct=0.0,
        dias_sin_reserva=0,
        ingreso_promedio_por_reserva=req.precio_actual,
        percentil_precio_zona=percentil,
        precio_vs_promedio_zona_pct=round(vs_avg, 1),
        modelo_usado=modelo, confianza=conf, puntos_de_datos=0,
    )
