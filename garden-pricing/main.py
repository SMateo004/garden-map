from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import logging

logger = logging.getLogger(__name__)
app = FastAPI(title="Garden Pricing Service")

class BookingRecord(BaseModel):
    date: str  # YYYY-MM-DD
    count: int
    revenue: float

class ForecastRequest(BaseModel):
    service_type: str  # PASEO or HOSPEDAJE
    history: List[BookingRecord]
    forecast_days: int = 7

class ForecastResponse(BaseModel):
    forecast_demand: float
    trend: str  # rising/stable/falling
    model_used: str
    confidence: str  # alta/media/baja
    seasonality_factors: dict

@app.post("/forecast", response_model=ForecastResponse)
async def forecast(req: ForecastRequest):
    try:
        history = req.history
        n = len(history)

        # Fallback por datos insuficientes
        if n < 5:
            return _rule_based_forecast(req)

        dates = [datetime.strptime(r.date, "%Y-%m-%d") for r in history]
        counts = [r.count for r in history]

        # ARIMA: funciona con datos cortos (5-29 registros)
        if n < 30:
            return _arima_forecast(dates, counts, req)

        # Prophet: para datos abundantes (30+)
        return _prophet_forecast(dates, counts, req)

    except Exception as e:
        logger.error(f"Forecast error: {e}")
        return _rule_based_forecast(req)

def _rule_based_forecast(req: ForecastRequest) -> ForecastResponse:
    """Reglas de estacionalidad cuando no hay suficientes datos."""
    today = datetime.now()
    dow = today.weekday()  # 0=lunes, 6=domingo

    # Factores base por día de semana (mayor demanda viernes-domingo)
    dow_factors = {0: 0.7, 1: 0.7, 2: 0.75, 3: 0.8, 4: 1.1, 5: 1.3, 6: 1.2}

    # Factor de mes (temporada alta: dic-ene, jul-ago en Bolivia)
    month = today.month
    month_factors = {1: 1.2, 2: 0.9, 3: 0.85, 4: 0.85, 5: 0.9, 6: 0.95,
                     7: 1.15, 8: 1.1, 9: 0.9, 10: 0.9, 11: 0.95, 12: 1.2}

    base_demand = 3.0 if req.service_type == "PASEO" else 1.5
    factor = dow_factors.get(dow, 1.0) * month_factors.get(month, 1.0)
    forecast_demand = base_demand * factor

    trend = "rising" if factor > 1.05 else "falling" if factor < 0.85 else "stable"

    return ForecastResponse(
        forecast_demand=round(forecast_demand, 2),
        trend=trend,
        model_used="reglas",
        confidence="baja",
        seasonality_factors={"dow_factor": dow_factors.get(dow, 1.0), "month_factor": month_factors.get(month, 1.0)}
    )

def _arima_forecast(dates, counts, req: ForecastRequest) -> ForecastResponse:
    """ARIMA para series cortas (5-29 puntos)."""
    try:
        from statsmodels.tsa.arima.model import ARIMA
        series = pd.Series(counts, index=pd.DatetimeIndex(dates))
        series = series.resample('D').sum().fillna(0)

        model = ARIMA(series, order=(1, 1, 1))
        result = model.fit()
        forecast = result.forecast(steps=req.forecast_days)
        avg_forecast = max(0, float(forecast.mean()))

        # Tendencia: comparar últimas 2 semanas vs primeras 2
        mid = len(counts) // 2
        trend_val = np.mean(counts[mid:]) - np.mean(counts[:mid])
        trend = "rising" if trend_val > 0.5 else "falling" if trend_val < -0.5 else "stable"

        return ForecastResponse(
            forecast_demand=round(avg_forecast, 2),
            trend=trend,
            model_used="arima",
            confidence="media",
            seasonality_factors={"data_points": len(counts)}
        )
    except Exception as e:
        logger.warning(f"ARIMA failed: {e}, falling back to rules")
        return _rule_based_forecast(req)

def _prophet_forecast(dates, counts, req: ForecastRequest) -> ForecastResponse:
    """Prophet para series largas (30+ puntos)."""
    try:
        from prophet import Prophet
        df = pd.DataFrame({"ds": dates, "y": counts})
        df = df.set_index("ds").resample("D").sum().reset_index()
        df.columns = ["ds", "y"]

        model = Prophet(yearly_seasonality=True, weekly_seasonality=True, daily_seasonality=False)
        # Feriados bolivianos básicos
        from prophet.make_holidays import make_holidays_df
        # Añadir manualmente si make_holidays_df no soporta BO
        model.fit(df)

        future = model.make_future_dataframe(periods=req.forecast_days)
        forecast_df = model.predict(future)
        next_period = forecast_df.tail(req.forecast_days)
        avg_forecast = max(0, float(next_period["yhat"].mean()))

        # Tendencia
        trend_slope = float(forecast_df["trend"].diff().tail(7).mean())
        trend = "rising" if trend_slope > 0.1 else "falling" if trend_slope < -0.1 else "stable"

        # Confianza basada en intervalo de predicción
        last_row = next_period.iloc[-1]
        interval_width = last_row["yhat_upper"] - last_row["yhat_lower"]
        confidence = "alta" if interval_width < avg_forecast * 0.5 else "media" if interval_width < avg_forecast else "baja"

        weekly_seasonality = {}
        if "weekly" in forecast_df.columns:
            weekly_seasonality = {"weekly_effect": round(float(next_period["weekly"].mean()), 3)}

        return ForecastResponse(
            forecast_demand=round(avg_forecast, 2),
            trend=trend,
            model_used="prophet+arima",
            confidence=confidence,
            seasonality_factors={**weekly_seasonality, "data_points": len(df)}
        )
    except Exception as e:
        logger.warning(f"Prophet failed: {e}, trying ARIMA")
        return _arima_forecast(dates, counts, req)

@app.get("/health")
async def health():
    return {"status": "ok", "service": "garden-pricing"}
