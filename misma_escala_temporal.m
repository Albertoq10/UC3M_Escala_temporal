
%% ============================================================
% ISEN + DELSYS
% UNA PRUEBA ESPECÍFICA
% ESCALA TEMPORAL COMÚN
% REFERENCIA: MÁXIMO DEL PEDAL REAL
% SIN FILTRADO
% SIN NORMALIZACIÓN DE AMPLITUD
% FRECUENCIA COMÚN = MAYOR FRECUENCIA DE MUESTREO
% UNA SOLA GRÁFICA SINCRONIZADA
% SALIDA EN EXCEL
% ============================================================

clc;
clear;
close all;


isen_file = "C:\UC3M_Trabajo\Ensayos_genesis_CSV_aceleracion\Ensayos_genesis_CSV_aceleracion\CSV\027\027_CA_01.csv";

delsys_file = "C:\UC3M_Trabajo\Ensayos_genesis_CSV_aceleracion\Ensayos_genesis_CSV_aceleracion\CSV_EMG\Ensayos\027\027_ENSAYO_1_Rep_1.1.csv";

output_folder = "C:\UC3M_Trabajo\Ensayos_genesis_CSV_aceleracion\Prueba_escala_temporal_comun";

if ~exist(output_folder, "dir")
    mkdir(output_folder);
end

%% ============================================================
% PARÁMETROS MODIFICABLES

% Parámetros para detección de estabilización:
% Se toma una ventana basal antes del máximo del pedal para estimar el
% comportamiento normal de cada señal. La estabilización se detecta cuando,
% después de la respuesta principal de cada sensor, la señal vuelve al rango
% basal definido como media ± k_std*STD y permanece dentro de ese rango
% durante duracion_estable segundos consecutivos.
% Ventana común alrededor del máximo del pedal

%media basal = valor promedio de la señal antes del frenado
%STD = desviación estándar de esa zona basal
%k_std = qué tan amplio quieres el rango

tiempo_antes = 1;       % segundos antes del máximo del pedal
tiempo_despues = 4;     % segundos después del máximo del pedal

% Ventana basal para estabilización
ventana_basal_ini = -1.0;
ventana_basal_fin = -0.5;

% Criterio de estabilización
duracion_estable = 0.5;   % segundos consecutivos dentro del rango basal
k_std = 1;                % basal ± 2*std

% Columna de tiempo en iSen
col_tiempo_isen = 85;

%% ============================================================
% COLUMNAS ISEN CORREGIDAS SEGÚN LA SEÑAL REAL

% Según lo observado:
%   iSen 5.A  = Cabeza
%   iSen 6.B  = Pecho
%   iSen 7.K  = Pedal real, aunque aparezca como vehículo
%   iSen 10.J = Vehículo real, aunque aparezca como pedal
%
% Si en otra prueba descubres que el mapeo cambia, se corrige aquí.

isen_cols.Cabeza   = [98 99 100];      % A - Cabeza
isen_cols.Pecho    = [101 102 103];    % B - Pecho
isen_cols.Vehiculo    = [104 105 106];    % K - Pedal real
isen_cols.Pedal = [113 114 115];    % J - Vehículo real

%% ============================================================
% LEER ARCHIVOS
% ============================================================

isen = readtable(isen_file, "VariableNamingRule", "preserve");
delsys = readtable(delsys_file, "VariableNamingRule", "preserve");

%% ============================================================
% EXTRAER ISEN

t_isen = convertirANumero(isen{:, col_tiempo_isen});

isen_data = struct();
campos_isen = fieldnames(isen_cols);

for i = 1:length(campos_isen)

    campo = campos_isen{i};
    cols = isen_cols.(campo);

    ax = convertirANumero(isen{:, cols(1)});
    ay = convertirANumero(isen{:, cols(2)});
    az = convertirANumero(isen{:, cols(3)});

    mag = sqrt(ax.^2 + ay.^2 + az.^2);

    valid = isfinite(t_isen) & isfinite(mag);

    isen_data.(campo).t = t_isen(valid);
    isen_data.(campo).mag = mag(valid);
    isen_data.(campo).cols = cols;

end

%% ============================================================
% EXTRAER DELSYS

% Delsys:
%   Sensor 9 = Cabeza
%   Sensores 10 y 11 = candidatos para pedal/vehículo
%
% El código asigna automáticamente:
%   sensor con mayor pico -> pedal real
%   sensor con menor pico -> vehículo real
%
% Esto evita depender de nombres o etiquetas incorrectas.

delsys_data = struct();

% Cabeza Delsys = sensor 9
[t_d_head, mag_d_head, idx_head, names_d] = extraerAccDelsysPorSensor( ...
    delsys, 9, "Delsys sensor 9 - Cabeza");

% Sensores candidatos 10 y 11
[t_d_10, mag_d_10, idx_10, ~] = extraerAccDelsysPorSensor( ...
    delsys, 10, "Delsys sensor 10");

[t_d_11, mag_d_11, idx_11, ~] = extraerAccDelsysPorSensor( ...
    delsys, 11, "Delsys sensor 11");

max_d_10 = max(mag_d_10, [], "omitnan");
max_d_11 = max(mag_d_11, [], "omitnan");

fprintf("\n===== ASIGNACIÓN FÍSICA DELSYS =====\n");
fprintf("Máximo Delsys sensor 10 = %.4f m/s²\n", max_d_10);
fprintf("Máximo Delsys sensor 11 = %.4f m/s²\n", max_d_11);

if max_d_10 >= max_d_11

    fprintf("Asignación: Delsys sensor 10 = PEDAL real\n");
    fprintf("Asignación: Delsys sensor 11 = VEHÍCULO real\n");

    t_d_pedal = t_d_10;
    mag_d_pedal = mag_d_10;
    idx_pedal = idx_10;
    sensor_pedal_delsys = "Sensor 10";

    t_d_car = t_d_11;
    mag_d_car = mag_d_11;
    idx_car = idx_11;
    sensor_vehiculo_delsys = "Sensor 11";

else

    fprintf("Asignación: Delsys sensor 11 = PEDAL real\n");
    fprintf("Asignación: Delsys sensor 10 = VEHÍCULO real\n");

    t_d_pedal = t_d_11;
    mag_d_pedal = mag_d_11;
    idx_pedal = idx_11;
    sensor_pedal_delsys = "Sensor 11";

    t_d_car = t_d_10;
    mag_d_car = mag_d_10;
    idx_car = idx_10;
    sensor_vehiculo_delsys = "Sensor 10";

end

% Guardar Delsys final
delsys_data.Cabeza.t = t_d_head;
delsys_data.Cabeza.mag = mag_d_head;
delsys_data.Cabeza.idxs = idx_head;
delsys_data.Cabeza.sensor = "Sensor 9";

delsys_data.Pedal.t = t_d_pedal;
delsys_data.Pedal.mag = mag_d_pedal;
delsys_data.Pedal.idxs = idx_pedal;
delsys_data.Pedal.sensor = sensor_pedal_delsys;

delsys_data.Vehiculo.t = t_d_car;
delsys_data.Vehiculo.mag = mag_d_car;
delsys_data.Vehiculo.idxs = idx_car;
delsys_data.Vehiculo.sensor = sensor_vehiculo_delsys;

%% ============================================================
% FRECUENCIAS DE MUESTREO
% ============================================================

fs_isen = estimarFs(isen_data.Pedal.t);
fs_delsys = estimarFs(delsys_data.Pedal.t);

% Criterio acordado:
% usar la frecuencia mayor para conservar la resolución de la señal más rápida
fs_common = max(fs_isen, fs_delsys);

fprintf("\n===== FRECUENCIAS =====\n");
fprintf("fs iSen   = %.4f Hz\n", fs_isen);
fprintf("fs Delsys = %.4f Hz\n", fs_delsys);
fprintf("fs común  = %.4f Hz\n", fs_common);

%% ============================================================
% EVENTO DE REFERENCIA: MÁXIMO DEL PEDAL REAL
% ============================================================
%
% No importa qué sistema empezó a grabar antes.
% Cada sistema se sincroniza con su propio máximo del pedal real:
%
%   t_rel_iSen   = t_iSen   - tmax_pedal_iSen
%   t_rel_Delsys = t_Delsys - tmax_pedal_Delsys
%
% Así ambos pedales quedan en t = 0.

[max_pedal_isen, idx_max_pedal_isen] = max(isen_data.Pedal.mag, [], "omitnan");
[max_pedal_delsys, idx_max_pedal_delsys] = max(delsys_data.Pedal.mag, [], "omitnan");

tmax_pedal_isen = isen_data.Pedal.t(idx_max_pedal_isen);
tmax_pedal_delsys = delsys_data.Pedal.t(idx_max_pedal_delsys);

desfase_pedales_original = tmax_pedal_delsys - tmax_pedal_isen;

fprintf("\n===== EVENTO DE REFERENCIA =====\n");
fprintf("Máximo pedal iSen real   = %.4f m/s² en t = %.4f s\n", ...
    max_pedal_isen, tmax_pedal_isen);

fprintf("Máximo pedal Delsys real = %.4f m/s² en t = %.4f s\n", ...
    max_pedal_delsys, tmax_pedal_delsys);

fprintf("Desfase original Delsys - iSen = %.4f s\n", ...
    desfase_pedales_original);

%% ============================================================
% TIEMPO COMÚN
% ============================================================
%% ============================================================
% VENTANA COMÚN AUTOMÁTICA CON DATOS VÁLIDOS
% ============================================================
%
% Objetivo:
%   Usar la mayor ventana posible dentro del rango deseado,
%   pero sin incluir zonas donde algún canal ya no tiene datos reales.
%
% Rango deseado:
%   -tiempo_antes a +tiempo_despues
%
% Rango real:
%   intersección de todos los canales disponibles después de sincronizar.

% Tiempos relativos iSen
t_rel_isen_pedal    = isen_data.Pedal.t    - tmax_pedal_isen;
t_rel_isen_vehiculo = isen_data.Vehiculo.t - tmax_pedal_isen;
t_rel_isen_pecho    = isen_data.Pecho.t    - tmax_pedal_isen;
t_rel_isen_cabeza   = isen_data.Cabeza.t   - tmax_pedal_isen;

% Tiempos relativos Delsys
t_rel_delsys_pedal    = delsys_data.Pedal.t    - tmax_pedal_delsys;
t_rel_delsys_vehiculo = delsys_data.Vehiculo.t - tmax_pedal_delsys;
t_rel_delsys_cabeza   = delsys_data.Cabeza.t   - tmax_pedal_delsys;

% Inicio común real: el inicio más tardío entre todos los canales
inicio_disponible = max([
    min(t_rel_isen_pedal)
    min(t_rel_isen_vehiculo)
    min(t_rel_isen_pecho)
    min(t_rel_isen_cabeza)
    min(t_rel_delsys_pedal)
    min(t_rel_delsys_vehiculo)
    min(t_rel_delsys_cabeza)
]);

% Fin común real: el final más temprano entre todos los canales
fin_disponible = min([
    max(t_rel_isen_pedal)
    max(t_rel_isen_vehiculo)
    max(t_rel_isen_pecho)
    max(t_rel_isen_cabeza)
    max(t_rel_delsys_pedal)
    max(t_rel_delsys_vehiculo)
    max(t_rel_delsys_cabeza)
]);

% Respetar el rango máximo que tú pediste,
% pero limitarlo a donde todos los canales tienen datos.
t_ini_common = max(-tiempo_antes, inicio_disponible);
t_fin_common = min(tiempo_despues, fin_disponible);

% Validación de seguridad
if t_fin_common <= t_ini_common
    error("No existe una ventana común válida entre todos los canales.");
end

% Crear tiempo común automático
t_common = (t_ini_common : 1/fs_common : t_fin_common)';

fprintf("\n===== VENTANA COMÚN AUTOMÁTICA =====\n");
fprintf("Ventana deseada: %.4f a %.4f s\n", -tiempo_antes, tiempo_despues);
fprintf("Inicio común disponible: %.4f s\n", inicio_disponible);
fprintf("Final común disponible:  %.4f s\n", fin_disponible);
fprintf("Ventana usada: %.4f a %.4f s\n", t_ini_common, t_fin_common);
fprintf("Duración usada: %.4f s\n", t_fin_common - t_ini_common);
fprintf("Número de muestras: %d\n", length(t_common));




%% ============================================================
% INTERPOLAR ISEN A TIEMPO COMÚN
% ============================================================

isen_sync = struct();

for i = 1:length(campos_isen)

    campo = campos_isen{i};

    t_rel = isen_data.(campo).t - tmax_pedal_isen;
    mag = isen_data.(campo).mag;

    isen_sync.(campo) = interp1( ...
        t_rel, ...
        mag, ...
        t_common, ...
        "linear", ...
        NaN);

end

%% ============================================================
% INTERPOLAR DELSYS A TIEMPO COMÚN
% ============================================================

delsys_sync = struct();
campos_delsys = fieldnames(delsys_data);

for i = 1:length(campos_delsys)

    campo = campos_delsys{i};

    t_rel = delsys_data.(campo).t - tmax_pedal_delsys;
    mag = delsys_data.(campo).mag;

    delsys_sync.(campo) = interp1( ...
        t_rel, ...
        mag, ...
        t_common, ...
        "linear", ...
        NaN);

end

%% ============================================================
% CALCULAR TIEMPOS DE ESTABILIZACIÓN PARA VISUALIZACIÓN
% ============================================================



% iSen
[t_est_isen_pedal, base_isen_pedal, std_isen_pedal, liminf_isen_pedal, limsup_isen_pedal] = ...
    detectarEstabilizacion(t_common, isen_sync.Pedal, ...
    ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common);

[t_est_isen_vehiculo, base_isen_vehiculo, std_isen_vehiculo, liminf_isen_vehiculo, limsup_isen_vehiculo] = ...
    detectarEstabilizacion(t_common, isen_sync.Vehiculo, ...
    ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common);

[t_est_isen_cabeza, base_isen_cabeza, std_isen_cabeza, liminf_isen_cabeza, limsup_isen_cabeza] = ...
    detectarEstabilizacion(t_common, isen_sync.Cabeza, ...
    ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common);

[t_est_isen_pecho, base_isen_pecho, std_isen_pecho, liminf_isen_pecho, limsup_isen_pecho] = ...
    detectarEstabilizacion(t_common, isen_sync.Pecho, ...
    ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common);

% Delsys
[t_est_delsys_pedal, base_delsys_pedal, std_delsys_pedal, liminf_delsys_pedal, limsup_delsys_pedal] = ...
    detectarEstabilizacion(t_common, delsys_sync.Pedal, ...
    ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common);

[t_est_delsys_vehiculo, base_delsys_vehiculo, std_delsys_vehiculo, liminf_delsys_vehiculo, limsup_delsys_vehiculo] = ...
    detectarEstabilizacion(t_common, delsys_sync.Vehiculo, ...
    ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common);

[t_est_delsys_cabeza, base_delsys_cabeza, std_delsys_cabeza, liminf_delsys_cabeza, limsup_delsys_cabeza] = ...
    detectarEstabilizacion(t_common, delsys_sync.Cabeza, ...
    ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common);


%% ============================================================
% CALCULAR MÁXIMOS Y TIEMPOS RELATIVOS AL PEDAL
% ============================================================

tabla_maximos = table();

tabla_maximos = [tabla_maximos; calcularMaximoCanal( ...
    "iSen", "Pedal real K", isen_data.Pedal.t, isen_data.Pedal.mag, tmax_pedal_isen, fs_isen)];

tabla_maximos = [tabla_maximos; calcularMaximoCanal( ...
    "iSen", "Vehículo real J", isen_data.Vehiculo.t, isen_data.Vehiculo.mag, tmax_pedal_isen, fs_isen)];

tabla_maximos = [tabla_maximos; calcularMaximoCanal( ...
    "iSen", "Pecho B", isen_data.Pecho.t, isen_data.Pecho.mag, tmax_pedal_isen, fs_isen)];

tabla_maximos = [tabla_maximos; calcularMaximoCanal( ...
    "iSen", "Cabeza A", isen_data.Cabeza.t, isen_data.Cabeza.mag, tmax_pedal_isen, fs_isen)];

tabla_maximos = [tabla_maximos; calcularMaximoCanal( ...
    "Delsys", "Pedal real " + delsys_data.Pedal.sensor, ...
    delsys_data.Pedal.t, delsys_data.Pedal.mag, tmax_pedal_delsys, fs_delsys)];

tabla_maximos = [tabla_maximos; calcularMaximoCanal( ...
    "Delsys", "Vehículo real " + delsys_data.Vehiculo.sensor, ...
    delsys_data.Vehiculo.t, delsys_data.Vehiculo.mag, tmax_pedal_delsys, fs_delsys)];

tabla_maximos = [tabla_maximos; calcularMaximoCanal( ...
    "Delsys", "Cabeza Sensor 9", ...
    delsys_data.Cabeza.t, delsys_data.Cabeza.mag, tmax_pedal_delsys, fs_delsys)];

%% ============================================================
% DETECTAR ESTABILIZACIÓN
% ============================================================

tabla_estabilizacion = table();

tabla_estabilizacion = [tabla_estabilizacion; calcularEstabilizacionCanal( ...
    "iSen", "Pedal real K", t_common, isen_sync.Pedal, ...
    ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common)];

tabla_estabilizacion = [tabla_estabilizacion; calcularEstabilizacionCanal( ...
    "iSen", "Vehículo real J", t_common, isen_sync.Vehiculo, ...
    ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common)];

tabla_estabilizacion = [tabla_estabilizacion; calcularEstabilizacionCanal( ...
    "iSen", "Pecho B", t_common, isen_sync.Pecho, ...
    ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common)];

tabla_estabilizacion = [tabla_estabilizacion; calcularEstabilizacionCanal( ...
    "iSen", "Cabeza A", t_common, isen_sync.Cabeza, ...
    ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common)];

tabla_estabilizacion = [tabla_estabilizacion; calcularEstabilizacionCanal( ...
    "Delsys", "Pedal real " + delsys_data.Pedal.sensor, t_common, delsys_sync.Pedal, ...
    ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common)];

tabla_estabilizacion = [tabla_estabilizacion; calcularEstabilizacionCanal( ...
    "Delsys", "Vehículo real " + delsys_data.Vehiculo.sensor, t_common, delsys_sync.Vehiculo, ...
    ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common)];

tabla_estabilizacion = [tabla_estabilizacion; calcularEstabilizacionCanal( ...
    "Delsys", "Cabeza Sensor 9", t_common, delsys_sync.Cabeza, ...
    ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common)];

%% ============================================================
% DATASET SINCRONIZADO
% ============================================================
%
% Cada fila = instante de tiempo común
% Cada columna = canal
%
% Esto todavía NO es el modelo de red neuronal.
% Solo es la señal temporalmente alineada, recortada e interpolada.

dataset_prueba = table( ...
    t_common, ...
    isen_sync.Pedal, ...
    isen_sync.Vehiculo, ...
    isen_sync.Pecho, ...
    isen_sync.Cabeza, ...
    delsys_sync.Pedal, ...
    delsys_sync.Vehiculo, ...
    delsys_sync.Cabeza, ...
    'VariableNames', { ...
        'Tiempo_relativo_s', ...
        'iSen_Pedal_real_K_ms2', ...
        'iSen_Vehiculo_real_J_ms2', ...
        'iSen_Pecho_B_ms2', ...
        'iSen_Cabeza_A_ms2', ...
        'Delsys_Pedal_real_ms2', ...
        'Delsys_Vehiculo_real_ms2', ...
        'Delsys_Cabeza_sensor9_ms2' ...
    } ...
);

%% ============================================================
% GRÁFICAS SINCRONIZADAS
% ============================================================
%
% Se generan:
%   1) Todas las señales juntas
%   2) Pedal iSen vs Delsys
%   3) Vehículo iSen vs Delsys
%   4) Cabeza iSen vs Delsys
%   5) Pecho iSen solo
%
% Todas están en la misma escala temporal:
%   t = 0 -> máximo del pedal real
%
%% ============================================================

%% ------------------------------------------------------------
% 1) GRÁFICA GENERAL: TODAS LAS SEÑALES
% ------------------------------------------------------------

fig_all = figure("Visible", "off");
fig_all.Position = [100 100 1500 850];

plot(t_common, isen_sync.Pedal, ...
    "LineWidth", 1.3, ...
    "DisplayName", "iSen Pedal real");

hold on;

plot(t_common, delsys_sync.Pedal, ...
    "LineWidth", 1.3, ...
    "DisplayName", "Delsys Pedal real " + delsys_data.Pedal.sensor);

plot(t_common, isen_sync.Vehiculo, ...
    "LineWidth", 1.1, ...
    "DisplayName", "iSen Vehículo real");

plot(t_common, delsys_sync.Vehiculo, ...
    "LineWidth", 1.1, ...
    "DisplayName", "Delsys Vehículo real " + delsys_data.Vehiculo.sensor);

plot(t_common, isen_sync.Cabeza, ...
    "LineWidth", 1.1, ...
    "DisplayName", "iSen Cabeza A");

plot(t_common, delsys_sync.Cabeza, ...
    "LineWidth", 1.1, ...
    "DisplayName", "Delsys Cabeza Sensor 9");

plot(t_common, isen_sync.Pecho, ...
    "LineWidth", 1.1, ...
    "DisplayName", "iSen Pecho B");

xline(0, "--", "Máximo pedal", ...
    "LabelOrientation", "aligned", ...
    "HandleVisibility", "off");

grid on;
box on;
legend("Location", "best");

xlabel("Tiempo relativo al máximo del pedal [s]");
ylabel("Magnitud de aceleración [m/s²]");

title("Todas las señales sincronizadas en escala temporal común");

subtitle(sprintf( ...
     "Ventana %.2f a %.2f s | fs común = %.2f Hz", ...
    t_ini_common, t_fin_common, fs_common));

out_fig_all = fullfile(output_folder, ...
    "01_todas_las_senales_sincronizadas.png");

exportgraphics(fig_all, out_fig_all, "Resolution", 200);
close(fig_all);

%% ------------------------------------------------------------
% PEDAL: ISEN VS DELSYS + ESTABILIZACIÓN
% ------------------------------------------------------------

fig_pedal = figure("Visible", "off");
fig_pedal.Position = [100 100 1400 750];

plot(t_common, isen_sync.Pedal, ...
    "LineWidth", 1.4, ...
    "DisplayName", "iSen Pedal");
hold on;

plot(t_common, delsys_sync.Pedal, ...
    "LineWidth", 1.4, ...
    "DisplayName", "Delsys Pedal");

xline(0, "--", "Máximo pedal", ...
    "HandleVisibility", "off");

if ~isnan(t_est_isen_pedal)
    xline(t_est_isen_pedal, ":", ...
        sprintf("Est. iSen %.2f s", t_est_isen_pedal), ...
        "HandleVisibility", "off");
    y_est = interp1(t_common, isen_sync.Pedal, t_est_isen_pedal, "linear", NaN);
    plot(t_est_isen_pedal, y_est, "o", "HandleVisibility", "off");
end

if ~isnan(t_est_delsys_pedal)
    xline(t_est_delsys_pedal, ":", ...
        sprintf("Est. Delsys %.2f s", t_est_delsys_pedal), ...
        "HandleVisibility", "off");
    y_est = interp1(t_common, delsys_sync.Pedal, t_est_delsys_pedal, "linear", NaN);
    plot(t_est_delsys_pedal, y_est, "o", "HandleVisibility", "off");
end

grid on;
box on;
legend("Location", "best");
xlabel("Tiempo relativo al máximo del pedal [s]");
ylabel("Magnitud de aceleración [m/s²]");
title("Pedal sincronizado - iSen vs Delsys");
subtitle("Se muestran tiempos de estabilización");

out_fig_pedal = fullfile(output_folder, "02_pedal_iSen_vs_Delsys_estabilizacion.png");
exportgraphics(fig_pedal, out_fig_pedal, "Resolution", 200);
close(fig_pedal);
%% ------------------------------------------------------------
% VEHÍCULO: ISEN VS DELSYS + ESTABILIZACIÓN
% ------------------------------------------------------------

fig_vehiculo = figure("Visible", "off");
fig_vehiculo.Position = [100 100 1400 750];

plot(t_common, isen_sync.Vehiculo, ...
    "LineWidth", 1.4, ...
    "DisplayName", "iSen Vehículo");
hold on;

plot(t_common, delsys_sync.Vehiculo, ...
    "LineWidth", 1.4, ...
    "DisplayName", "Delsys Vehículo");

xline(0, "--", "Máximo pedal", ...
    "HandleVisibility", "off");

if ~isnan(t_est_isen_vehiculo)
    xline(t_est_isen_vehiculo, ":", ...
        sprintf("Est. iSen %.2f s", t_est_isen_vehiculo), ...
        "HandleVisibility", "off");
    y_est = interp1(t_common, isen_sync.Vehiculo, t_est_isen_vehiculo, "linear", NaN);
    plot(t_est_isen_vehiculo, y_est, "o", "HandleVisibility", "off");
end

if ~isnan(t_est_delsys_vehiculo)
    xline(t_est_delsys_vehiculo, ":", ...
        sprintf("Est. Delsys %.2f s", t_est_delsys_vehiculo), ...
        "HandleVisibility", "off");
    y_est = interp1(t_common, delsys_sync.Vehiculo, t_est_delsys_vehiculo, "linear", NaN);
    plot(t_est_delsys_vehiculo, y_est, "o", "HandleVisibility", "off");
end

grid on;
box on;
legend("Location", "best");
xlabel("Tiempo relativo al máximo del pedal [s]");
ylabel("Magnitud de aceleración [m/s²]");
title("Vehículo sincronizado - iSen vs Delsys");
subtitle("Se muestran tiempos de estabilización");

out_fig_vehiculo = fullfile(output_folder, "03_vehiculo_iSen_vs_Delsys_estabilizacion.png");
exportgraphics(fig_vehiculo, out_fig_vehiculo, "Resolution", 200);
close(fig_vehiculo);
%% ------------------------------------------------------------
% CABEZA: ISEN VS DELSYS + ESTABILIZACIÓN
% ------------------------------------------------------------

fig_cabeza = figure("Visible", "off");
fig_cabeza.Position = [100 100 1400 750];

plot(t_common, isen_sync.Cabeza, ...
    "LineWidth", 1.4, ...
    "DisplayName", "iSen Cabeza");
hold on;

plot(t_common, delsys_sync.Cabeza, ...
    "LineWidth", 1.4, ...
    "DisplayName", "Delsys Cabeza");

xline(0, "--", "Máximo pedal", ...
    "HandleVisibility", "off");

if ~isnan(t_est_isen_cabeza)
    xline(t_est_isen_cabeza, ":", ...
        sprintf("Est. iSen %.2f s", t_est_isen_cabeza), ...
        "HandleVisibility", "off");
    y_est = interp1(t_common, isen_sync.Cabeza, t_est_isen_cabeza, "linear", NaN);
    plot(t_est_isen_cabeza, y_est, "o", "HandleVisibility", "off");
end

if ~isnan(t_est_delsys_cabeza)
    xline(t_est_delsys_cabeza, ":", ...
        sprintf("Est. Delsys %.2f s", t_est_delsys_cabeza), ...
        "HandleVisibility", "off");
    y_est = interp1(t_common, delsys_sync.Cabeza, t_est_delsys_cabeza, "linear", NaN);
    plot(t_est_delsys_cabeza, y_est, "o", "HandleVisibility", "off");
end

grid on;
box on;
legend("Location", "best");
xlabel("Tiempo relativo al máximo del pedal [s]");
ylabel("Magnitud de aceleración [m/s²]");
title("Cabeza sincronizada - iSen vs Delsys");
subtitle("Se muestran tiempos de estabilización");

out_fig_cabeza = fullfile(output_folder, "04_cabeza_iSen_vs_Delsys_estabilizacion.png");
exportgraphics(fig_cabeza, out_fig_cabeza, "Resolution", 200);
close(fig_cabeza);

%% ------------------------------------------------------------
% PECHO: ISEN SOLO + ESTABILIZACIÓN
% ------------------------------------------------------------

fig_pecho = figure("Visible", "off");
fig_pecho.Position = [100 100 1400 750];

plot(t_common, isen_sync.Pecho, ...
    "LineWidth", 1.4, ...
    "DisplayName", "iSen Pecho");
hold on;

xline(0, "--", "Máximo pedal", ...
    "HandleVisibility", "off");

if ~isnan(t_est_isen_pecho)
    xline(t_est_isen_pecho, ":", ...
        sprintf("Est. iSen %.2f s", t_est_isen_pecho), ...
        "HandleVisibility", "off");
    y_est = interp1(t_common, isen_sync.Pecho, t_est_isen_pecho, "linear", NaN);
    plot(t_est_isen_pecho, y_est, "o", "HandleVisibility", "off");
end

grid on;
box on;
legend("Location", "best");
xlabel("Tiempo relativo al máximo del pedal [s]");
ylabel("Magnitud de aceleración [m/s²]");
title("Pecho sincronizado - iSen");
subtitle("Se muestra tiempo de estabilización");

out_fig_pecho = fullfile(output_folder, "05_pecho_iSen_estabilizacion.png");
exportgraphics(fig_pecho, out_fig_pecho, "Resolution", 200);
close(fig_pecho);
%% ------------------------------------------------------------
% MOSTRAR RUTAS GENERADAS
% ------------------------------------------------------------

fprintf("\n===== GRÁFICAS GENERADAS =====\n");
fprintf("General:  %s\n", out_fig_all);
fprintf("Pedal:    %s\n", out_fig_pedal);
fprintf("Vehículo: %s\n", out_fig_vehiculo);
fprintf("Cabeza:   %s\n", out_fig_cabeza);
fprintf("Pecho:    %s\n", out_fig_pecho);


%% ============================================================
% GUARDAR EXCEL
% ============================================================

out_excel = fullfile(output_folder, ...
    "resultado_escala_temporal_comun.xlsx");

writetable(tabla_maximos, out_excel, "Sheet", "Maximos");
writetable(tabla_estabilizacion, out_excel, "Sheet", "Estabilizacion");
writetable(dataset_prueba, out_excel, "Sheet", "Dataset_sincronizado");

fprintf("\n========================================\n");
fprintf("Proceso terminado.\n");
fprintf("Excel guardado en:\n%s\n", out_excel);
fprintf("Gráfica guardada en:\n%s\n", out_fig_all);
fprintf("========================================\n");

%% ============================================================
% FUNCIONES AUXILIARES
% ============================================================

function [t, mag, idxs, names_d] = extraerAccDelsysPorSensor(delsys, sensor_num, nombre_sensor)

    names_d = string(delsys.Properties.VariableNames);
    names_upper = upper(names_d);

    sensor_num_str = string(sensor_num);
    patron_sensor = "SENSOR " + sensor_num_str;

    % Buscar primero usando "SENSOR 10", "SENSOR 11", etc.
    idx_ax = find(contains(names_upper, patron_sensor) & contains(names_upper, "ACC.X"), 1);
    idx_ay = find(contains(names_upper, patron_sensor) & contains(names_upper, "ACC.Y"), 1);
    idx_az = find(contains(names_upper, patron_sensor) & contains(names_upper, "ACC.Z"), 1);

    % Si no encuentra con "SENSOR 10", buscar con número suelto
    if isempty(idx_ax) || isempty(idx_ay) || isempty(idx_az)

        idx_ax = find(contains(names_upper, "ACC.X") & contains(names_upper, sensor_num_str), 1);
        idx_ay = find(contains(names_upper, "ACC.Y") & contains(names_upper, sensor_num_str), 1);
        idx_az = find(contains(names_upper, "ACC.Z") & contains(names_upper, sensor_num_str), 1);

    end

    if isempty(idx_ax) || isempty(idx_ay) || isempty(idx_az)

        disp("Columnas Delsys disponibles:");
        disp(names_d');

        error("No encontré ACC.X/Y/Z para %s.", nombre_sensor);

    end

    %% --------------------------------------------------------
    % Buscar columna de tiempo cercana
    % --------------------------------------------------------
    %
    % En tus archivos puede estar antes o después de ACC.X.
    % Probamos primero después y luego antes.

    idx_t = NaN;

    if idx_ax + 1 <= width(delsys)

        posible_t = convertirANumero(delsys{:, idx_ax + 1});

        if sum(isfinite(posible_t)) > 10
            idx_t = idx_ax + 1;
        end

    end

    if isnan(idx_t) && idx_ax - 1 >= 1

        posible_t = convertirANumero(delsys{:, idx_ax - 1});

        if sum(isfinite(posible_t)) > 10
            idx_t = idx_ax - 1;
        end

    end

    if isnan(idx_t)

        error("No pude localizar columna de tiempo para %s.", nombre_sensor);

    end

    %% --------------------------------------------------------
    % Extraer datos
    % --------------------------------------------------------

    t = convertirANumero(delsys{:, idx_t});

    ax = convertirANumero(delsys{:, idx_ax});
    ay = convertirANumero(delsys{:, idx_ay});
    az = convertirANumero(delsys{:, idx_az});

    mag = sqrt(ax.^2 + ay.^2 + az.^2);

    valid = isfinite(t) & isfinite(mag);

    t = t(valid);
    mag = mag(valid);

    idxs.idx_t = idx_t;
    idxs.idx_ax = idx_ax;
    idxs.idx_ay = idx_ay;
    idxs.idx_az = idx_az;

    fprintf("\n%s:\n", nombre_sensor);
    fprintf("Tiempo: columna %d -> %s\n", idx_t, names_d(idx_t));
    fprintf("ACC.X:  columna %d -> %s\n", idx_ax, names_d(idx_ax));
    fprintf("ACC.Y:  columna %d -> %s\n", idx_ay, names_d(idx_ay));
    fprintf("ACC.Z:  columna %d -> %s\n", idx_az, names_d(idx_az));
    fprintf("Máximo: %.4f m/s²\n", max(mag, [], "omitnan"));

end

function fila = calcularMaximoCanal(sistema, sensor, t, mag, tmax_pedal, fs)

    [max_val, idx_max] = max(mag, [], "omitnan");

    tmax_original = t(idx_max);
    tmax_relativo_pedal = tmax_original - tmax_pedal;

    fila = table( ...
        string(sistema), ...
        string(sensor), ...
        max_val, ...
        tmax_original, ...
        tmax_relativo_pedal, ...
        fs, ...
        'VariableNames', { ...
            'Sistema', ...
            'Sensor', ...
            'Maximo_ms2', ...
            'Tiempo_Maximo_Original_s', ...
            'Tiempo_Maximo_Relativo_Pedal_s', ...
            'Frecuencia_Muestreo_Hz' ...
        } ...
    );

end

function fila = calcularEstabilizacionCanal( ...
    sistema, sensor, t, senal, basal_ini, basal_fin, duracion_estable, k_std, fs)

    [t_estable, base, desv, lim_inf, lim_sup, t_inicio_busqueda] = detectarEstabilizacion( ...
        t, senal, basal_ini, basal_fin, duracion_estable, k_std, fs);

    fila = table( ...
        string(sistema), ...
        string(sensor), ...
        base, ...
        desv, ...
        lim_inf, ...
        lim_sup, ...
        t_inicio_busqueda, ...
        t_estable, ...
        'VariableNames', { ...
            'Sistema', ...
            'Sensor', ...
            'Media_Basal_ms2', ...
            'STD_Basal_ms2', ...
            'Limite_Inferior_ms2', ...
            'Limite_Superior_ms2', ...
            'Tiempo_Inicio_Busqueda_s', ...
            'Tiempo_Estabilizacion_s' ...
        } ...
    );

end

function [t_estable, base, desv, lim_inf, lim_sup, t_inicio_busqueda] = detectarEstabilizacion( ...
    t, senal, basal_ini, basal_fin, duracion_estable, k_std, fs)

    t_estable = NaN;
    t_inicio_busqueda = NaN;

    %% --------------------------------------------------------
    % 1) Calcular basal antes del pedal
    % --------------------------------------------------------

    mask_base = ...
        t >= basal_ini & ...
        t <= basal_fin & ...
        isfinite(senal);

    if sum(mask_base) < 5

        base = NaN;
        desv = NaN;
        lim_inf = NaN;
        lim_sup = NaN;
        return;

    end

    base = mean(senal(mask_base), "omitnan");
    desv = std(senal(mask_base), "omitnan");

    lim_inf = base - k_std * desv;
    lim_sup = base + k_std * desv;

    %% --------------------------------------------------------
    % 2) Buscar el máximo propio de la señal después del pedal
    % --------------------------------------------------------
    %
    % En lugar de buscar estabilización desde t = 0,
    % buscamos primero la respuesta principal de ESA señal.

    idx_despues_pedal = find(t >= 0 & isfinite(senal));

    if isempty(idx_despues_pedal)
        return;
    end

    [~, idx_max_local] = max(senal(idx_despues_pedal), [], "omitnan");

    idx_max_senal = idx_despues_pedal(idx_max_local);

    t_inicio_busqueda = t(idx_max_senal);

    %% --------------------------------------------------------
    % 3) Buscar estabilización después del máximo propio
    % --------------------------------------------------------

    dentro = ...
        senal >= lim_inf & ...
        senal <= lim_sup & ...
        isfinite(senal);

    idx_post = find(t >= t_inicio_busqueda & isfinite(senal));

    if isempty(idx_post)
        return;
    end

    n_consecutivos = max(3, round(duracion_estable * fs));

    for k = 1:length(idx_post) - n_consecutivos + 1

        idx_ini = idx_post(k);
        idx_fin = idx_ini + n_consecutivos - 1;

        if idx_fin > length(senal)
            break;
        end

        if all(dentro(idx_ini:idx_fin))
            t_estable = t(idx_ini);
            return;
        end

    end

end
function fs = estimarFs(t)

    t = t(isfinite(t));

    if length(t) < 2
        fs = NaN;
        return;
    end

    dt = median(diff(t), "omitnan");

    if isnan(dt) || dt <= 0
        fs = NaN;
    else
        fs = 1 / dt;
    end

end

function x = convertirANumero(x)

    if isnumeric(x)

        x = double(x);
        return;

    end

    if iscell(x)

        x = string(x);

    end

    if isstring(x) || ischar(x) || iscategorical(x)

        x = string(x);
        x = strrep(x, ",", ".");
        x = str2double(x);
        return;

    end

    error("Tipo de dato no reconocido para conversión numérica.");

end

