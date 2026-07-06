import pandas as pd
import numpy as np
from scipy import stats
import matplotlib.pyplot as plt

archivo = r"C:\UC3M_Trabajo\Ensayos_genesis_CSV_aceleracion\Procesamiento_Completo_iSen_Delsys\resumen_metricas_estadistica.xlsx"

df = pd.read_excel(archivo)

df["Detecto_Estabilizacion"] = np.where(
    df["Tiempo_Estabilizacion_s"].notna(),
    1,
    0
)

metricas = [
    "Maximo_ms2",
    "Tiempo_Maximo_Relativo_Pedal_s",
    "Rango_Pico_Basal_ms2",
    "Tiempo_Estabilizacion_s",
    "RMS_PostEvento_ms2",
    "Area_PostEvento_ms2_s"
]

# Resumen descriptivo
resumen = df.groupby(["Condicion", "Sistema", "Sensor"])[metricas].agg(
    ["count", "mean", "std", "median", "min", "max"]
)

print(resumen)

# Comparación CA vs SA con Mann-Whitney
resultados = []

for metrica in metricas:
    for (sistema, sensor), datos in df.groupby(["Sistema", "Sensor"]):

        ca = datos.loc[datos["Condicion"] == "CA", metrica].dropna()
        sa = datos.loc[datos["Condicion"] == "SA", metrica].dropna()

        if len(ca) >= 2 and len(sa) >= 2:
            stat, p = stats.mannwhitneyu(ca, sa, alternative="two-sided")

            resultados.append({
                "Sistema": sistema,
                "Sensor": sensor,
                "Metrica": metrica,
                "n_CA": len(ca),
                "n_SA": len(sa),
                "Media_CA": ca.mean(),
                "Media_SA": sa.mean(),
                "Mediana_CA": ca.median(),
                "Mediana_SA": sa.median(),
                "p_value": p
            })

resultados = pd.DataFrame(resultados)

salida_excel = r"C:\UC3M_Trabajo\Ensayos_genesis_CSV_aceleracion\Procesamiento_Completo_iSen_Delsys\analisis_estadistico_resultados.xlsx"

with pd.ExcelWriter(salida_excel, engine="openpyxl") as writer:
    resumen.to_excel(writer, sheet_name="Resumen_descriptivo")
    resultados.to_excel(writer, sheet_name="CA_vs_SA", index=False)

print("Análisis guardado en:", salida_excel)