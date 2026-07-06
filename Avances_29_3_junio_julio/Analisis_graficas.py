import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from scipy import stats

# ============================================================
# RUTAS
# ============================================================

base_folder = r"C:\UC3M_Trabajo\Ensayos_genesis_CSV_aceleracion\Procesamiento_Completo_iSen_Delsys"

archivo_csv = os.path.join(base_folder, "resumen_metricas_estadistica.csv")

output_excel = os.path.join(base_folder, "analisis_estadistico_resultados.xlsx")
output_figuras = os.path.join(base_folder, "Figuras_Estadistica")

os.makedirs(output_figuras, exist_ok=True)

# ============================================================
# CARGAR DATOS
# ============================================================

df = pd.read_csv(archivo_csv)

print("Datos cargados:")
print(df.head())
print("\nColumnas:")
print(df.columns.tolist())

# ============================================================
# LIMPIEZA BASICA
# ============================================================

# Asegurar que estas columnas sean texto
for col in ["Caso", "Condicion", "Sistema", "Sensor"]:
    if col in df.columns:
        df[col] = df[col].astype(str)

# Asegurar que las métricas sean numéricas
metricas_base = [
    "Maximo_ms2",
    "Tiempo_Maximo_Relativo_Pedal_s",
    "Rango_Pico_Basal_ms2",
    "Tiempo_Estabilizacion_s",
    "RMS_PostEvento_ms2",
    "Area_PostEvento_ms2_s"
]

for col in metricas_base:
    df[col] = pd.to_numeric(df[col], errors="coerce")

# Crear variable binaria de estabilización
df["Detecto_Estabilizacion"] = np.where(
    df["Tiempo_Estabilizacion_s"].notna(),
    1,
    0
)

# ============================================================
# NORMALIZACION RESPECTO AL PEDAL
# ============================================================
# Para cada Caso + Condicion + Prueba + Sistema, busca el pedal de ese mismo sistema.
# Luego divide las métricas del sensor entre la métrica equivalente del pedal.
# Esto ayuda a controlar que no todas las frenadas tuvieron la misma intensidad.

pedal_rows = df[df["Sensor"].str.contains("Pedal", case=False, na=False)].copy()

pedal_ref = pedal_rows[
    [
        "Caso",
        "Condicion",
        "Prueba",
        "Sistema",
        "Maximo_ms2",
        "Rango_Pico_Basal_ms2",
        "RMS_PostEvento_ms2",
        "Area_PostEvento_ms2_s"
    ]
].rename(columns={
    "Maximo_ms2": "Pedal_Maximo_ms2",
    "Rango_Pico_Basal_ms2": "Pedal_Rango_Pico_Basal_ms2",
    "RMS_PostEvento_ms2": "Pedal_RMS_PostEvento_ms2",
    "Area_PostEvento_ms2_s": "Pedal_Area_PostEvento_ms2_s"
})

df = df.merge(
    pedal_ref,
    on=["Caso", "Condicion", "Prueba", "Sistema"],
    how="left"
)

def safe_divide(a, b):
    return np.where((b.notna()) & (b != 0), a / b, np.nan)

df["Maximo_Normalizado_Pedal"] = safe_divide(
    df["Maximo_ms2"],
    df["Pedal_Maximo_ms2"]
)

df["Rango_Normalizado_Pedal"] = safe_divide(
    df["Rango_Pico_Basal_ms2"],
    df["Pedal_Rango_Pico_Basal_ms2"]
)

df["RMS_Normalizado_Pedal"] = safe_divide(
    df["RMS_PostEvento_ms2"],
    df["Pedal_RMS_PostEvento_ms2"]
)

df["Area_Normalizada_Pedal"] = safe_divide(
    df["Area_PostEvento_ms2_s"],
    df["Pedal_Area_PostEvento_ms2_s"]
)

metricas_analisis = metricas_base + [
    "Maximo_Normalizado_Pedal",
    "Rango_Normalizado_Pedal",
    "RMS_Normalizado_Pedal",
    "Area_Normalizada_Pedal"
]

# ============================================================
# RESUMEN DESCRIPTIVO
# ============================================================

resumen_descriptivo = df.groupby(
    ["Condicion", "Sistema", "Sensor"]
)[metricas_analisis].agg(
    ["count", "mean", "std", "median", "min", "max"]
)

# ============================================================
# PORCENTAJE DE ESTABILIZACION DETECTADA
# ============================================================

resumen_estabilizacion = df.groupby(
    ["Condicion", "Sistema", "Sensor"]
)["Detecto_Estabilizacion"].agg(
    count="count",
    porcentaje_detectado=lambda x: 100 * x.mean()
).reset_index()

# ============================================================
# COMPARACION CA VS SA
# ============================================================

resultados_tests = []

for metrica in metricas_analisis:
    for (sistema, sensor), datos in df.groupby(["Sistema", "Sensor"]):

        ca = datos.loc[datos["Condicion"] == "CA", metrica].dropna()
        sa = datos.loc[datos["Condicion"] == "SA", metrica].dropna()

        if len(ca) >= 2 and len(sa) >= 2:

            # Mann-Whitney: prueba no paramétrica, útil si no asumimos normalidad
            stat, p_value = stats.mannwhitneyu(
                ca,
                sa,
                alternative="two-sided"
            )

            resultados_tests.append({
                "Sistema": sistema,
                "Sensor": sensor,
                "Metrica": metrica,
                "n_CA": len(ca),
                "n_SA": len(sa),
                "Media_CA": ca.mean(),
                "Media_SA": sa.mean(),
                "Mediana_CA": ca.median(),
                "Mediana_SA": sa.median(),
                "STD_CA": ca.std(),
                "STD_SA": sa.std(),
                "p_value_MannWhitney": p_value
            })

resultados_tests = pd.DataFrame(resultados_tests)

# ============================================================
# FUNCIONES DE GRAFICAS
# ============================================================

def limpiar_nombre(nombre):
    nombre = str(nombre)
    reemplazos = {
        " ": "_",
        "/": "_",
        "\\": "_",
        ":": "_",
        "*": "_",
        "?": "_",
        '"': "",
        "<": "",
        ">": "",
        "|": "_"
    }
    for a, b in reemplazos.items():
        nombre = nombre.replace(a, b)
    return nombre


def guardar_boxplot(df, sistema, sensor, metrica, carpeta):
    datos = df[
        (df["Sistema"] == sistema) &
        (df["Sensor"] == sensor)
    ].copy()

    if datos.empty:
        return

    ca = datos.loc[datos["Condicion"] == "CA", metrica].dropna()
    sa = datos.loc[datos["Condicion"] == "SA", metrica].dropna()

    if len(ca) == 0 or len(sa) == 0:
        return

    plt.figure(figsize=(7, 5))
    plt.boxplot([ca, sa], tick_labels=["CA", "SA"])
    plt.ylabel(metrica)
    plt.title(f"{metrica}\n{sistema} - {sensor}")
    plt.grid(True, alpha=0.3)

    nombre = f"boxplot_{sistema}_{sensor}_{metrica}.png"
    ruta = os.path.join(carpeta, limpiar_nombre(nombre))

    plt.savefig(ruta, dpi=300, bbox_inches="tight")
    plt.close()


def guardar_barra_estabilizacion(df, carpeta):
    datos = df.groupby(
        ["Condicion", "Sistema", "Sensor"]
    )["Detecto_Estabilizacion"].mean().reset_index()

    datos["Porcentaje"] = datos["Detecto_Estabilizacion"] * 100

    for (sistema, sensor), sub in datos.groupby(["Sistema", "Sensor"]):
        ca = sub.loc[sub["Condicion"] == "CA", "Porcentaje"]
        sa = sub.loc[sub["Condicion"] == "SA", "Porcentaje"]

        if ca.empty and sa.empty:
            continue

        valores = [
            ca.iloc[0] if not ca.empty else np.nan,
            sa.iloc[0] if not sa.empty else np.nan
        ]

        plt.figure(figsize=(7, 5))
        plt.bar(["CA", "SA"], valores)
        plt.ylabel("% estabilización detectada")
        plt.ylim(0, 100)
        plt.title(f"Porcentaje de estabilización detectada\n{sistema} - {sensor}")
        plt.grid(True, axis="y", alpha=0.3)

        nombre = f"estabilizacion_{sistema}_{sensor}.png"
        ruta = os.path.join(carpeta, limpiar_nombre(nombre))

        plt.savefig(ruta, dpi=300, bbox_inches="tight")
        plt.close()


def guardar_scatter_pedal(df, sistema, sensor, metrica_sensor, carpeta):
    datos = df[
        (df["Sistema"] == sistema) &
        (df["Sensor"] == sensor)
    ].copy()

    if datos.empty:
        return

    if "Pedal_Maximo_ms2" not in datos.columns:
        return

    datos = datos.dropna(subset=["Pedal_Maximo_ms2", metrica_sensor])

    if datos.empty:
        return

    plt.figure(figsize=(7, 5))

    for condicion in ["CA", "SA"]:
        sub = datos[datos["Condicion"] == condicion]
        if not sub.empty:
            plt.scatter(
                sub["Pedal_Maximo_ms2"],
                sub[metrica_sensor],
                label=condicion,
                alpha=0.8
            )

    plt.xlabel("Máximo del pedal [m/s²]")
    plt.ylabel(metrica_sensor)
    plt.title(f"{metrica_sensor} vs máximo del pedal\n{sistema} - {sensor}")
    plt.legend()
    plt.grid(True, alpha=0.3)

    nombre = f"scatter_pedal_{sistema}_{sensor}_{metrica_sensor}.png"
    ruta = os.path.join(carpeta, limpiar_nombre(nombre))

    plt.savefig(ruta, dpi=300, bbox_inches="tight")
    plt.close()


# ============================================================
# GENERAR BOXPLOTS AUTOMATICOS
# ============================================================

sensores_unicos = df[["Sistema", "Sensor"]].drop_duplicates()

for _, row in sensores_unicos.iterrows():
    sistema = row["Sistema"]
    sensor = row["Sensor"]

    for metrica in metricas_analisis:
        guardar_boxplot(df, sistema, sensor, metrica, output_figuras)

# ============================================================
# GRAFICAS DE ESTABILIZACION
# ============================================================

guardar_barra_estabilizacion(df, output_figuras)

# ============================================================
# SCATTERS CONTRA MAXIMO DEL PEDAL
# ============================================================
# Evitamos graficar pedal contra pedal.

metricas_scatter = [
    "Maximo_ms2",
    "Rango_Pico_Basal_ms2",
    "RMS_PostEvento_ms2",
    "Area_PostEvento_ms2_s"
]

for _, row in sensores_unicos.iterrows():
    sistema = row["Sistema"]
    sensor = row["Sensor"]

    if "Pedal" in sensor:
        continue

    for metrica in metricas_scatter:
        guardar_scatter_pedal(df, sistema, sensor, metrica, output_figuras)

# ============================================================
# GUARDAR EXCEL FINAL
# ============================================================

with pd.ExcelWriter(output_excel, engine="openpyxl") as writer:
    df.to_excel(writer, sheet_name="Datos_con_normalizacion", index=False)
    resumen_descriptivo.to_excel(writer, sheet_name="Resumen_descriptivo")
    resumen_estabilizacion.to_excel(writer, sheet_name="Estabilizacion")
    resultados_tests.to_excel(writer, sheet_name="CA_vs_SA", index=False)

print("\n========================================")
print("Analisis terminado.")
print("Excel guardado en:")
print(output_excel)
print("Figuras guardadas en:")
print(output_figuras)
print("========================================")