"""
garden-pricing — Motor estadístico de precios
Modelos (orden de prioridad según datos disponibles):
  1. Prophet + SARIMA + XGBoost  → ensemble ponderado (≥90 días)
  2. SARIMA + XGBoost            → ensemble (≥30 días)
  3. SARIMA                      → solo SARIMA (≥15 días)
  4. XGBoost                     → solo features de calendario (≥7 días)
  5. Reglas                      → patrones estáticos (<7 días)
  LSTM opcional: activa si TensorFlow está instalado y hay ≥180 días de datos.
Feriados: Bolivia + Santa Cruz de la Sierra (Carnaval, Aniversario, Día de la Madre).
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd
from fastapi import FastAPI
from pydantic import BaseModel

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

# ── Dependencias opcionales ────────────────────────────────────────────────
try:
    import xgboost as xgb
    _XGB_AVAILABLE = True
except ImportError:
    _XGB_AVAILABLE = False
    logger.warning("xgboost no disponible — XGBoost desactivado")

try:
    import tensorflow as tf
    from tensorflow import keras  # type: ignore
    _LSTM_AVAILABLE = True
    tf.get_logger().setLevel("ERROR")
except ImportError:
    _LSTM_AVAILABLE = False

# ── FastAPI ────────────────────────────────────────────────────────────────
app = FastAPI(title="Garden Pricing Engine", version="2.0.0")


# ── Schemas ────────────────────────────────────────────────────────────────
class BookingRecord(BaseModel):
    date: str       # YYYY-MM-DD
    count: int
    revenue: float
    price: float = 0.0

class AnalyzeRequest(BaseModel):
    service_type: str           # PASEO | HOSPEDAJE
    history: List[BookingRecord]
    precio_actual: float
    precio_promedio_zona: float
    precio_min_zona: float
    precio_max_zona: float
    forecast_days: int = 7

class PricingAnalysis(BaseModel):
    demanda_forecast_7d: float
    demanda_forecast_30d: float
    tendencia: str                      # rising | stable | falling
    fuerza_tendencia: float             # 0–1
    precio_optimo_matematico: int
    elasticidad_precio: float
    ingreso_proyectado_actual: float
    ingreso_proyectado_optimo: float
    mejora_ingreso_pct: float
    rango_precio_seguro: Dict[str, int]
    factor_estacional_actual: float
    dias_peak_proximos_7: List[str]
    dias_slow_proximos_7: List[str]
    patron_semanal: Dict[str, float]
    reservas_7d: int
    reservas_30d: int
    reservas_90d: int
    variacion_vs_mes_anterior_pct: float
    dias_sin_reserva: int
    ingreso_promedio_por_reserva: float
    percentil_precio_zona: float
    precio_vs_promedio_zona_pct: float
    modelo_usado: str
    confianza: str                      # alta | media | baja
    puntos_de_datos: int


# ── Endpoints ──────────────────────────────────────────────────────────────
@app.post("/analyze", response_model=PricingAnalysis)
async def analyze(req: AnalyzeRequest) -> PricingAnalysis:
    try:
        return _run_full_analysis(req)
    except Exception as exc:
        logger.error("[analyze] Error inesperado: %s", exc, exc_info=True)
        return _fallback_analysis(req)


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "service": "garden-pricing-engine",
        "models": {
            "prophet": True,
            "sarima": True,
            "xgboost": _XGB_AVAILABLE,
            "lstm": _LSTM_AVAILABLE,
        },
    }


# ── Motor principal ────────────────────────────────────────────────────────
def _run_full_analysis(req: AnalyzeRequest) -> PricingAnalysis:
    df = _build_df(req)
    n_active = int((df["y"] > 0).sum())

    # Demanda: ensemble o modelo individual según datos disponibles
    d7, d30, trend, strength, modelo, confianza = _forecast_demand(df, req, n_active)

    # Elasticidad y precio óptimo
    elasticidad = _estimate_elasticity(df, req.service_type)
    p_opt, ing_act, ing_opt, mejora = _optimize_price(
        req.precio_actual, d7, elasticidad,
        req.precio_min_zona, req.precio_max_zona,
    )

    # Estacionalidad
    patron = _weekly_pattern(df)
    factor_hoy = _current_seasonal_factor(patron)
    dias_peak, dias_slow = _classify_next_days(patron, req.forecast_days)

    # Estadísticas históricas
    now = datetime.now()
    reservas_7d  = int(df[df["ds"] >= now - timedelta(days=7)]["y"].sum())
    reservas_30d = int(df[df["ds"] >= now - timedelta(days=30)]["y"].sum())
    reservas_90d = int(df["y"].sum())

    prev30 = int(df[
        (df["ds"] >= now - timedelta(days=60)) &
        (df["ds"] <  now - timedelta(days=30))
    ]["y"].sum())
    variacion_pct = ((reservas_30d - prev30) / max(1, prev30)) * 100 if prev30 > 0 else 0.0

    active_df = df[df["y"] > 0]
    dias_sin_reserva = (
        int((now - active_df["ds"].max()).days) if not active_df.empty else 90
    )
    ing_por_reserva = float(df[df["y"] > 0]["revenue"].mean()) if not active_df.empty else req.precio_actual

    # Posición en mercado
    percentil = _price_percentile(req.precio_actual, req.precio_min_zona, req.precio_max_zona)
    vs_avg = ((req.precio_actual - req.precio_promedio_zona) / max(1, req.precio_promedio_zona)) * 100

    rango = {
        "min": max(int(req.precio_min_zona), int(req.precio_actual * 0.85)),
        "max": min(int(req.precio_max_zona), int(req.precio_actual * 1.20)),
    }

    return PricingAnalysis(
        demanda_forecast_7d=round(d7, 2),
        demanda_forecast_30d=round(d30, 2),
        tendencia=trend,
        fuerza_tendencia=round(strength, 2),
        precio_optimo_matematico=p_opt,
        elasticidad_precio=round(elasticidad, 2),
        ingreso_proyectado_actual=round(ing_act, 2),
        ingreso_proyectado_optimo=round(ing_opt, 2),
        mejora_ingreso_pct=round(mejora, 1),
        rango_precio_seguro=rango,
        factor_estacional_actual=round(factor_hoy, 2),
        dias_peak_proximos_7=dias_peak,
        dias_slow_proximos_7=dias_slow,
        patron_semanal=patron,
        reservas_7d=reservas_7d,
        reservas_30d=reservas_30d,
        reservas_90d=reservas_90d,
        variacion_vs_mes_anterior_pct=round(variacion_pct, 1),
        dias_sin_reserva=dias_sin_reserva,
        ingreso_promedio_por_reserva=round(ing_por_reserva, 2),
        percentil_precio_zona=round(percentil, 1),
        precio_vs_promedio_zona_pct=round(vs_avg, 1),
        modelo_usado=modelo,
        confianza=confianza,
        puntos_de_datos=len(df),
    )


def _build_df(req: AnalyzeRequest) -> pd.DataFrame:
    """Construye DataFrame diario con relleno de 0 para días sin datos."""
    if not req.history:
        return pd.DataFrame(columns=["ds", "y", "revenue", "price"])

    rows = [
        {
            "ds": datetime.strptime(r.date, "%Y-%m-%d"),
            "y": r.count,
            "revenue": r.revenue,
            "price": r.price if r.price > 0 else req.precio_actual,
        }
        for r in req.history
    ]
    df = pd.DataFrame(rows)
    df = (
        df.set_index("ds")
        .resample("D")
        .agg({"y": "sum", "revenue": "sum", "price": "mean"})
        .fillna(0)
        .reset_index()
    )
    df["price"] = df["price"].replace(0, req.precio_actual)
    return df


# ── Forecasting ────────────────────────────────────────────────────────────
def _forecast_demand(
    df: pd.DataFrame, req: AnalyzeRequest, n_active: int
) -> Tuple[float, float, str, float, str, str]:
    """Selecciona modelo(s) y devuelve (d7, d30, trend, strength, modelo, confianza)."""

    if n_active < 7:
        return _rules_forecast(req)

    forecasts: List[Tuple[float, float, str, float]] = []  # (d7, d30, trend, strength)
    modelos_usados: List[str] = []

    # ── XGBoost (feature-based, funciona con pocos datos) ──
    if _XGB_AVAILABLE and n_active >= 7:
        result = _xgboost_forecast(df, req)
        if result:
            forecasts.append(result)
            modelos_usados.append("xgboost")

    # ── SARIMA (necesita ≥15 días activos para estimar parámetros estacionales) ──
    if n_active >= 15:
        result = _sarima_forecast(df, req)
        if result:
            forecasts.append(result)
            modelos_usados.append("sarima")

    # ── Prophet (necesita ≥30 días para capturar estacionalidad semanal+anual) ──
    if n_active >= 30:
        result = _prophet_forecast(df, req)
        if result:
            forecasts.append(result)
            modelos_usados.append("prophet")

    # ── LSTM (necesita ≥180 días para evitar sobreajuste) ──
    if _LSTM_AVAILABLE and n_active >= 180:
        result = _lstm_forecast(df, req)
        if result:
            forecasts.append(result)
            modelos_usados.append("lstm")

    if not forecasts:
        return _rules_forecast(req)

    # Ensemble ponderado: más peso a Prophet > SARIMA > XGBoost > LSTM
    weights_map = {"prophet": 0.40, "sarima": 0.35, "xgboost": 0.20, "lstm": 0.05}
    total_w = sum(weights_map.get(m, 0.10) for m in modelos_usados)
    d7  = sum(f[0] * weights_map.get(m, 0.10) / total_w for f, m in zip(forecasts, modelos_usados))
    d30 = sum(f[1] * weights_map.get(m, 0.10) / total_w for f, m in zip(forecasts, modelos_usados))

    # Tendencia por mayoría
    trend_votes = [f[2] for f in forecasts]
    trend = max(set(trend_votes), key=trend_votes.count)
    strength = float(np.mean([f[3] for f in forecasts]))

    modelo = "+".join(modelos_usados)
    confianza = "alta" if len(modelos_usados) >= 3 else ("media" if len(modelos_usados) >= 2 else "media")

    return max(0.0, d7), max(0.0, d30), trend, round(strength, 2), modelo, confianza


def _rules_forecast(req: AnalyzeRequest) -> Tuple[float, float, str, float, str, str]:
    """Forecast basado en patrones estáticos de Bolivia/Santa Cruz."""
    today = datetime.now()
    dow   = today.weekday()
    month = today.month

    dow_factors   = {0: 0.70, 1: 0.70, 2: 0.75, 3: 0.80, 4: 1.10, 5: 1.30, 6: 1.20}
    month_factors = {1: 1.20, 2: 1.30, 3: 0.85, 4: 0.85, 5: 1.10,  6: 0.95,
                     7: 1.15, 8: 1.10, 9: 0.90, 10: 0.90, 11: 0.95, 12: 1.20}

    base = 3.0 if req.service_type == "PASEO" else 1.5
    f    = dow_factors.get(dow, 1.0) * month_factors.get(month, 1.0)
    d7   = base * f
    d30  = base * month_factors.get(month, 1.0)
    trend = "rising" if f > 1.05 else ("falling" if f < 0.85 else "stable")
    return d7, d30, trend, round(abs(f - 1.0), 2), "reglas", "baja"


def _sarima_forecast(df: pd.DataFrame, req: AnalyzeRequest) -> Optional[Tuple[float, float, str, float]]:
    """
    SARIMA(1,1,1)(1,1,1)[7] — captura tendencia + estacionalidad semanal.
    Usa statsmodels SARIMAX.
    """
    try:
        from statsmodels.tsa.statespace.sarimax import SARIMAX

        series = df.set_index("ds")["y"].asfreq("D").fillna(0)

        # Modelo con orden estacional semanal (s=7)
        model = SARIMAX(
            series,
            order=(1, 1, 1),
            seasonal_order=(1, 1, 1, 7),
            enforce_stationarity=False,
            enforce_invertibility=False,
        )
        fit = model.fit(disp=False, maxiter=200)

        fc7  = fit.forecast(steps=7)
        fc30 = fit.forecast(steps=30)

        d7  = max(0.0, float(fc7.mean()))
        d30 = max(0.0, float(fc30.mean()))

        # Tendencia a partir de la componente de nivel
        vals = series.values
        mid  = len(vals) // 2
        slope = np.mean(vals[mid:]) - np.mean(vals[:mid])
        trend = "rising" if slope > 0.3 else ("falling" if slope < -0.3 else "stable")
        strength = min(1.0, abs(slope) / max(1.0, np.mean(vals)))

        return d7, d30, trend, round(strength, 2)
    except Exception as exc:
        logger.warning("[SARIMA] falló: %s", exc)
        return None


def _prophet_forecast(df: pd.DataFrame, req: AnalyzeRequest) -> Optional[Tuple[float, float, str, float]]:
    """
    Prophet con:
    - Estacionalidad semanal (weekly) + anual (yearly)
    - Estacionalidad mensual adicional (fourier_order=3)
    - Feriados bolivianos + Santa Cruz
    - Modo multiplicativo para capturar picos de feriados
    """
    try:
        from prophet import Prophet  # type: ignore

        train = df[["ds", "y"]].copy()
        holidays_df = _bolivian_holidays_df()

        m = Prophet(
            yearly_seasonality=True,
            weekly_seasonality=True,
            daily_seasonality=False,
            holidays=holidays_df,
            seasonality_mode="multiplicative",
            changepoint_prior_scale=0.05,
        )
        m.add_seasonality(name="monthly", period=30.5, fourier_order=3)
        m.fit(train)

        fut7  = m.make_future_dataframe(periods=7,  freq="D")
        fut30 = m.make_future_dataframe(periods=30, freq="D")
        fc7   = m.predict(fut7)
        fc30  = m.predict(fut30)

        d7  = max(0.0, float(fc7.tail(7)["yhat"].clip(lower=0).mean()))
        d30 = max(0.0, float(fc30.tail(30)["yhat"].clip(lower=0).mean()))

        trend_slope  = float(fc7["trend"].diff().tail(7).mean())
        trend = "rising" if trend_slope > 0.1 else ("falling" if trend_slope < -0.1 else "stable")
        strength = min(1.0, abs(trend_slope) / max(0.1, d7))

        return d7, d30, trend, round(strength, 2)
    except Exception as exc:
        logger.warning("[Prophet] falló: %s", exc)
        return None


def _xgboost_forecast(df: pd.DataFrame, req: AnalyzeRequest) -> Optional[Tuple[float, float, str, float]]:
    """
    XGBoost con features de calendario: día de semana, semana del año, mes,
    es_feriado, lags (1, 7, 14), rolling mean 7 días.
    """
    if not _XGB_AVAILABLE:
        return None
    try:
        holidays_set = _bolivian_holidays_set()
        feat_df = _make_xgb_features(df, holidays_set)

        target_col = "y"
        feature_cols = [c for c in feat_df.columns if c not in ("ds", target_col)]

        # Necesitamos al menos lag_14 disponible
        feat_df = feat_df.dropna(subset=feature_cols)
        if len(feat_df) < 5:
            return None

        X = feat_df[feature_cols].values
        y = feat_df[target_col].values

        model = xgb.XGBRegressor(
            n_estimators=200,
            max_depth=4,
            learning_rate=0.05,
            subsample=0.8,
            colsample_bytree=0.8,
            objective="reg:squarederror",
            verbosity=0,
        )
        model.fit(X, y)

        # Pronosticar iterativamente los próximos 30 días
        last_known = df["y"].values.copy().tolist()
        last_date  = df["ds"].max()
        preds: List[float] = []

        for step in range(1, 31):
            next_date = last_date + timedelta(days=step)
            lag1  = last_known[-1]  if len(last_known) >= 1  else 0.0
            lag7  = last_known[-7]  if len(last_known) >= 7  else 0.0
            lag14 = last_known[-14] if len(last_known) >= 14 else 0.0
            roll7 = float(np.mean(last_known[-7:])) if len(last_known) >= 7 else lag1

            row = _build_xgb_row(next_date, lag1, lag7, lag14, roll7, holidays_set)
            x_row = np.array([[row[c] for c in feature_cols]])
            pred = max(0.0, float(model.predict(x_row)[0]))
            preds.append(pred)
            last_known.append(pred)

        d7  = float(np.mean(preds[:7]))
        d30 = float(np.mean(preds[:30]))

        # Tendencia: comparar primera mitad vs segunda mitad del pronóstico 30d
        mid = len(preds) // 2
        slope = np.mean(preds[mid:]) - np.mean(preds[:mid])
        trend = "rising" if slope > 0.2 else ("falling" if slope < -0.2 else "stable")
        strength = min(1.0, abs(slope) / max(0.1, d30))

        return d7, d30, trend, round(strength, 2)
    except Exception as exc:
        logger.warning("[XGBoost] falló: %s", exc)
        return None


def _lstm_forecast(df: pd.DataFrame, req: AnalyzeRequest) -> Optional[Tuple[float, float, str, float]]:
    """
    LSTM univariado de 1 capa con ventana de 14 días.
    Solo activa si TensorFlow está instalado y hay ≥180 días de datos.
    """
    if not _LSTM_AVAILABLE:
        return None
    try:
        from sklearn.preprocessing import MinMaxScaler  # type: ignore

        lookback = 14
        series = df["y"].values.reshape(-1, 1).astype(float)

        scaler = MinMaxScaler()
        scaled = scaler.fit_transform(series)

        # Crear secuencias X, y
        X_list, y_list = [], []
        for i in range(lookback, len(scaled)):
            X_list.append(scaled[i - lookback:i])
            y_list.append(scaled[i])
        if not X_list:
            return None
        X_arr = np.array(X_list)
        y_arr = np.array(y_list)

        model = keras.Sequential([
            keras.layers.LSTM(32, input_shape=(lookback, 1), return_sequences=False),
            keras.layers.Dropout(0.1),
            keras.layers.Dense(1),
        ])
        model.compile(optimizer="adam", loss="mse")
        model.fit(X_arr, y_arr, epochs=60, batch_size=16, verbose=0)

        # Forecast iterativo 30 días
        window = list(scaled[-lookback:].flatten())
        preds_scaled: List[float] = []
        for _ in range(30):
            x_in = np.array(window[-lookback:]).reshape(1, lookback, 1)
            p    = float(model.predict(x_in, verbose=0)[0, 0])
            preds_scaled.append(p)
            window.append(p)

        preds = scaler.inverse_transform(np.array(preds_scaled).reshape(-1, 1)).flatten()
        preds = np.clip(preds, 0, None)

        d7  = float(np.mean(preds[:7]))
        d30 = float(np.mean(preds[:30]))
        mid = len(preds) // 2
        slope = np.mean(preds[mid:]) - np.mean(preds[:mid])
        trend = "rising" if slope > 0.2 else ("falling" if slope < -0.2 else "stable")
        strength = min(1.0, abs(slope) / max(0.1, d30))

        return d7, d30, trend, round(strength, 2)
    except Exception as exc:
        logger.warning("[LSTM] falló: %s", exc)
        return None


# ── XGBoost features ───────────────────────────────────────────────────────
def _make_xgb_features(df: pd.DataFrame, holidays_set: set) -> pd.DataFrame:
    f = df.copy()
    f["dow"]         = f["ds"].dt.dayofweek
    f["week"]        = f["ds"].dt.isocalendar().week.astype(int)
    f["month"]       = f["ds"].dt.month
    f["day_of_year"] = f["ds"].dt.dayofyear
    f["is_weekend"]  = (f["dow"] >= 5).astype(int)
    f["is_holiday"]  = f["ds"].dt.strftime("%Y-%m-%d").isin(holidays_set).astype(int)
    f["lag_1"]       = f["y"].shift(1)
    f["lag_7"]       = f["y"].shift(7)
    f["lag_14"]      = f["y"].shift(14)
    f["rolling_7"]   = f["y"].shift(1).rolling(7).mean()
    return f


def _build_xgb_row(date: datetime, lag1: float, lag7: float, lag14: float,
                   roll7: float, holidays_set: set) -> dict:
    return {
        "dow":         date.weekday(),
        "week":        date.isocalendar()[1],
        "month":       date.month,
        "day_of_year": date.timetuple().tm_yday,
        "is_weekend":  int(date.weekday() >= 5),
        "is_holiday":  int(date.strftime("%Y-%m-%d") in holidays_set),
        "lag_1":       lag1,
        "lag_7":       lag7,
        "lag_14":      lag14,
        "rolling_7":   roll7,
    }


# ── Elasticidad y optimización ─────────────────────────────────────────────
def _estimate_elasticity(df: pd.DataFrame, service_type: str) -> float:
    """
    Regresión log-log:  log(demand) = α + β·log(price)  → β = elasticidad.
    Requiere ≥10 puntos con variación de precio > 5%.
    Fallback: valores por sector (PASEO más elástico que HOSPEDAJE).
    """
    defaults = {"PASEO": -1.2, "HOSPEDAJE": -0.8}
    try:
        prices  = df["price"].values
        demands = df["y"].values
        price_range = prices.max() - prices.min() if len(prices) > 0 else 0
        if len(prices) < 10 or price_range < prices.mean() * 0.05:
            return defaults.get(service_type, -1.0)

        mask = (prices > 0) & (demands > 0)
        if mask.sum() < 10:
            return defaults.get(service_type, -1.0)

        log_p = np.log(prices[mask])
        log_d = np.log(demands[mask])
        A = np.vstack([np.ones_like(log_p), log_p]).T
        beta = float(np.linalg.lstsq(A, log_d, rcond=None)[0][1])
        return float(np.clip(beta, -2.5, -0.3))
    except Exception:
        return defaults.get(service_type, -1.0)


def _optimize_price(
    precio_actual: float,
    demanda_7d: float,
    elasticidad: float,
    precio_min: float,
    precio_max: float,
) -> Tuple[int, float, float, float]:
    """
    Maximiza ingresos con D(p) = D₀·(p/p₀)^ε.
    Precio óptimo: p* = p₀·ε/(ε+1) cuando ε < -1 (elástico).
    """
    if demanda_7d <= 0:
        return int(precio_actual), 0.0, 0.0, 0.0

    ing_actual = precio_actual * demanda_7d

    if elasticidad < -1:
        p_opt_raw = precio_actual * (elasticidad / (elasticidad + 1))
    else:
        p_opt_raw = precio_max  # inelástico → sube hasta el techo

    p_opt = int(np.clip(round(p_opt_raw), precio_min, precio_max))

    d_opt   = demanda_7d * ((p_opt / precio_actual) ** elasticidad)
    ing_opt = p_opt * d_opt
    mejora  = ((ing_opt - ing_actual) / max(1, ing_actual)) * 100

    return p_opt, round(ing_actual, 2), round(ing_opt, 2), round(mejora, 1)


# ── Estacionalidad ─────────────────────────────────────────────────────────
_DAYS_ES = ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"]
_DOW_DEFAULT = {d: v for d, v in zip(_DAYS_ES, [0.70, 0.70, 0.75, 0.80, 1.10, 1.30, 1.20])}


def _weekly_pattern(df: pd.DataFrame) -> Dict[str, float]:
    if df.empty or df["y"].sum() == 0:
        return dict(_DOW_DEFAULT)

    tmp = df.copy()
    tmp["dow"] = tmp["ds"].dt.dayofweek
    avg = tmp.groupby("dow")["y"].mean()
    global_avg = avg.mean()
    if global_avg == 0:
        return {d: 1.0 for d in _DAYS_ES}

    return {
        name: round(float(avg.get(i, global_avg) / global_avg), 2)
        for i, name in enumerate(_DAYS_ES)
    }


def _current_seasonal_factor(patron: Dict[str, float]) -> float:
    return patron.get(_DAYS_ES[datetime.now().weekday()], 1.0)


def _classify_next_days(patron: Dict[str, float], n_days: int) -> Tuple[List[str], List[str]]:
    today = datetime.now()
    peak, slow = [], []
    for i in range(1, n_days + 1):
        day    = today + timedelta(days=i)
        factor = patron.get(_DAYS_ES[day.weekday()], 1.0)
        label  = day.strftime("%Y-%m-%d")
        if factor >= 1.15:
            peak.append(label)
        elif factor <= 0.80:
            slow.append(label)
    return peak, slow


# ── Mercado ────────────────────────────────────────────────────────────────
def _price_percentile(precio: float, p_min: float, p_max: float) -> float:
    if p_max <= p_min:
        return 50.0
    return float(np.clip((precio - p_min) / (p_max - p_min) * 100, 0, 100))


# ── Feriados Bolivia / Santa Cruz ──────────────────────────────────────────
def _bolivian_holidays_list(year: int) -> List[Tuple[str, str]]:
    """
    Feriados nacionales + Santa Cruz de la Sierra.
    Carnaval varía cada año (domingo antes del Miércoles de Ceniza).
    """
    # Calcular Carnaval (lunes y martes antes de Miércoles de Ceniza)
    ash_wednesday = _ash_wednesday(year)
    carnival_mon  = (ash_wednesday - timedelta(days=2)).strftime("%Y-%m-%d")
    carnival_tue  = (ash_wednesday - timedelta(days=1)).strftime("%Y-%m-%d")

    fixed = [
        (f"{year}-01-01", "Año Nuevo"),
        (f"{year}-01-22", "Día del Estado Plurinacional"),
        (carnival_mon,    "Carnaval lunes"),
        (carnival_tue,    "Carnaval martes"),
        (f"{year}-05-01", "Día del Trabajo"),
        (f"{year}-05-27", "Día de la Madre"),
        (f"{year}-06-21", "Año Nuevo Andino-Amazónico"),
        (f"{year}-08-06", "Día de la Independencia"),
        (f"{year}-09-24", "Día del Departamento de Santa Cruz"),
        (f"{year}-10-12", "Día de la Hispanidad"),
        (f"{year}-11-02", "Día de los Difuntos"),
        (f"{year}-12-25", "Navidad"),
    ]
    return fixed


def _ash_wednesday(year: int) -> datetime:
    """Miércoles de Ceniza usando el algoritmo de Gauss para Pascua."""
    a = year % 19
    b = year // 100
    c = year % 100
    d = b // 4
    e = b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i = c // 4
    k = c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    day   = ((h + l - 7 * m + 114) % 31) + 1
    easter = datetime(year, month, day)
    return easter - timedelta(days=46)


def _bolivian_holidays_df() -> pd.DataFrame:
    """DataFrame con feriados del año actual y siguiente (para Prophet)."""
    year = datetime.now().year
    rows = _bolivian_holidays_list(year) + _bolivian_holidays_list(year + 1)
    df = pd.DataFrame(rows, columns=["ds", "holiday"])
    df["ds"] = pd.to_datetime(df["ds"])
    return df


def _bolivian_holidays_set() -> set:
    """Set de fechas YYYY-MM-DD para lookup rápido en XGBoost."""
    year = datetime.now().year
    return {date for date, _ in _bolivian_holidays_list(year) + _bolivian_holidays_list(year + 1)}


# ── Fallback ───────────────────────────────────────────────────────────────
def _fallback_analysis(req: AnalyzeRequest) -> PricingAnalysis:
    d7, d30, trend, strength, modelo, conf = _rules_forecast(req)
    patron = _weekly_pattern(pd.DataFrame())
    peak, slow = _classify_next_days(patron, req.forecast_days)
    p_opt, ing_act, ing_opt, mejora = _optimize_price(
        req.precio_actual, d7, -1.0, req.precio_min_zona, req.precio_max_zona
    )
    percentil = _price_percentile(req.precio_actual, req.precio_min_zona, req.precio_max_zona)
    vs_avg = ((req.precio_actual - req.precio_promedio_zona) / max(1, req.precio_promedio_zona)) * 100

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
