%% ============================================================
% ISEN + DELSYS
% AUTOMATIZACION COMPLETA DE PREPROCESAMIENTO Y METRICAS
%
% Este script:
%   1) Recorre automaticamente las carpetas de iSen.
%   2) Busca la carpeta correspondiente de Delsys.
%   3) Empareja archivos por numero de prueba.
%   4) Extrae aceleracion de:
%        iSen: Pedal, Vehiculo, Cabeza, Pecho
%        Delsys: Pedal, Vehiculo, Cabeza
%   5) Calcula magnitud = sqrt(X^2 + Y^2 + Z^2).
%   6) Sincroniza usando el maximo del pedal real como t = 0.
%   7) Crea ventana comun automatica.
%   8) Interpola a una frecuencia comun.
%   9) Calcula metricas para analisis estadistico.
%  10) Guarda CSV sincronizado por prueba.
%  11) Guarda graficas por prueba.
%  12) Guarda Excel global de metricas.
%
% Sin filtrado.
% Sin normalizacion de amplitud.
% Unidades conservadas como m/s^2.
% ============================================================

clc;
clear;
close all;



isen_root = "C:\UC3M_Trabajo\Ensayos_genesis_CSV_aceleracion\Ensayos_genesis_CSV_aceleracion\CSV";

delsys_root = "C:\UC3M_Trabajo\Ensayos_genesis_CSV_aceleracion\Ensayos_genesis_CSV_aceleracion\CSV_EMG\Ensayos";

output_root = "C:\UC3M_Trabajo\Ensayos_genesis_CSV_aceleracion\Procesamiento_Completo_iSen_Delsys";

if ~exist(output_root, "dir")
    mkdir(output_root);
end

%% ============================================================
% PARAMETROS MODIFICABLES

% Deteccion de muerte de senal
% Si una senal cae cerca de cero y permanece asi durante cierto tiempo,
% se considera que dejo de registrar correctamente.
umbral_muerte_senal = 0.05;      % m/s^2, valor cercano a cero
duracion_muerte_senal = 0.10;    % segundos consecutivos cerca de cero
margen_antes_muerte = 0.02;      % margen para cortar antes de la caida
% Ventana comun alrededor del maximo del pedal
tiempo_antes = 1;       % segundos antes del maximo del pedal
tiempo_despues = 4;     % segundos despues del maximo del pedal

% Parametros para deteccion de estabilizacion:
% Se toma una ventana basal antes del maximo del pedal para estimar el
% comportamiento normal de cada senal. La estabilizacion se detecta cuando,
% despues de la respuesta principal de cada sensor, la senal vuelve al rango
% basal definido como media +/- k_std*STD y permanece dentro de ese rango
% durante duracion_estable segundos consecutivos.

ventana_basal_ini = -1.0;
ventana_basal_fin = -0.5;

duracion_estable = 0.5;   % segundos consecutivos dentro del rango basal
k_std = 2;                % basal +/- k_std*STD

% procesar todo, deja Inf.
%
max_carpetas = Inf;

% Columna de tiempo en iSen
col_tiempo_isen = 85;

% Columnas iSen corregidas segun la senal real
isen_cols.Cabeza   = [98 99 100];      % A - Cabeza
isen_cols.Pecho    = [101 102 103];    % B - Pecho
isen_cols.Vehiculo = [104 105 106];    % K - Vehiculo real
isen_cols.Pedal    = [113 114 115];    % J - Pedal real

%% =========================================================
% TABLAS GLOBALES
% ======
resultados_metricas = table();

resumen = table( ...
    strings(0,1), ...
    strings(0,1), ...
    strings(0,1), ...
    strings(0,1), ...
    strings(0,1), ...
    'VariableNames', {'Caso', 'Condicion', 'Prueba', 'Estado', 'Mensaje'} ...
);

%% ============================================================
% LISTAR CARPETAS ISEN


isen_dirs = dir(isen_root);
isen_dirs = isen_dirs([isen_dirs.isdir]);
isen_dirs = isen_dirs(~ismember({isen_dirs.name}, {'.','..'}));

mask_num = false(length(isen_dirs), 1);

for i = 1:length(isen_dirs)
    mask_num(i) = ~isempty(regexp(isen_dirs(i).name, '^\d+$', 'once'));
end

isen_dirs = isen_dirs(mask_num);

if isfinite(max_carpetas)
    n_cases = min(max_carpetas, length(isen_dirs));
    isen_dirs = isen_dirs(1:n_cases);
end

%% ============================================================
% RECORRER CASOS
% ==============================

for i = 1:length(isen_dirs)

    case_id = string(isen_dirs(i).name);

    fprintf("\n========================================\n");
    fprintf("Procesando caso %s\n", case_id);
    fprintf("========================================\n");

    isen_folder = fullfile(isen_root, case_id);

    % Delsys puede tener carpeta 027_GENESIS o 027
    delsys_folder_1 = fullfile(delsys_root, case_id + "_GENESIS");
    delsys_folder_2 = fullfile(delsys_root, case_id);

    if exist(delsys_folder_1, "dir")
        delsys_folder = delsys_folder_1;
    elseif exist(delsys_folder_2, "dir")
        delsys_folder = delsys_folder_2;
    else
        fprintf("No existe carpeta Delsys para caso %s. Se omite.\n", case_id);

        resumen = addResumen( ...
            resumen, case_id, "", "", ...
            "OMITIDA", "No existe carpeta Delsys");

        continue;
    end

    %% ========================================================
    % LISTAR ARCHIVOS


    isen_files = listarArchivosDatos(isen_folder);
    delsys_files = listarArchivosDatos(delsys_folder);

    if isempty(isen_files)
        fprintf("No hay archivos iSen en caso %s.\n", case_id);

        resumen = addResumen( ...
            resumen, case_id, "", "", ...
            "OMITIDA", "No hay archivos iSen");

        continue;
    end

    if isempty(delsys_files)
        fprintf("No hay archivos Delsys en caso %s.\n", case_id);

        resumen = addResumen( ...
            resumen, case_id, "", "", ...
            "OMITIDA", "No hay archivos Delsys");

        continue;
    end

    %% ========================================================
    % INFO ARCHIVOS ISEN
 

    isen_info = table( ...
        zeros(0,1), ...
        strings(0,1), ...
        strings(0,1), ...
        strings(0,1), ...
        'VariableNames', {'trial_num', 'condition', 'file_name', 'full_path'} ...
    );

    for k = 1:length(isen_files)

        file_name = string(isen_files(k).name);
        full_path = string(fullfile(isen_files(k).folder, isen_files(k).name));

        [trial_num, condition] = extraerInfoISen(file_name);

        new_row = table( ...
            trial_num, ...
            condition, ...
            file_name, ...
            full_path, ...
            'VariableNames', {'trial_num', 'condition', 'file_name', 'full_path'} ...
        );

        isen_info = [isen_info; new_row];
    end

    %% ========================================================
    % INFO ARCHIVOS DELSYS
    %
    delsys_info = table( ...
        zeros(0,1), ...
        strings(0,1), ...
        strings(0,1), ...
        'VariableNames', {'trial_num', 'file_name', 'full_path'} ...
    );

    for k = 1:length(delsys_files)

        file_name = string(delsys_files(k).name);
        full_path = string(fullfile(delsys_files(k).folder, delsys_files(k).name));

        trial_num = extraerEnsayoDelsys(file_name);

        new_row = table( ...
            trial_num, ...
            file_name, ...
            full_path, ...
            'VariableNames', {'trial_num', 'file_name', 'full_path'} ...
        );

        delsys_info = [delsys_info; new_row];
    end

    %% ========================================================
    % CREAR CARPETA DE SALIDA DEL CASO
    

    output_case_folder = fullfile(output_root, case_id);

    if ~exist(output_case_folder, "dir")
        mkdir(output_case_folder);
    end

    %% ========================================================
    % PROCESAR CADA ARCHIVO ISEN CON SU DELSYS CORRESPONDIENTE
    

    for k = 1:height(isen_info)

        try

            trial = isen_info.trial_num(k);
            condition = isen_info.condition(k);

            if isnan(trial)
                resumen = addResumen( ...
                    resumen, case_id, condition, "", ...
                    "OMITIDA", "No se pudo extraer numero de prueba iSen");
                continue;
            end

            idx_delsys = find(delsys_info.trial_num == trial, 1);

            if isempty(idx_delsys)
                fprintf("No hay archivo Delsys para caso %s | %s | prueba %d\n", ...
                    case_id, condition, trial);

                resumen = addResumen( ...
                    resumen, case_id, condition, string(trial), ...
                    "OMITIDA", "No hay archivo Delsys para esa prueba");

                continue;
            end

            isen_file = isen_info.full_path(k);
            delsys_file = delsys_info.full_path(idx_delsys);

            fprintf("\n----------------------------------------\n");
            fprintf("Caso %s | %s | prueba %d\n", case_id, condition, trial);
            fprintf("iSen:   %s\n", isen_info.file_name(k));
            fprintf("Delsys: %s\n", delsys_info.file_name(idx_delsys));

            tabla_metricas_prueba = procesarPruebaCompleta( ...
                isen_file, ...
                delsys_file, ...
                case_id, ...
                condition, ...
                trial, ...
                output_case_folder, ...
                col_tiempo_isen, ...
                isen_cols, ...
                tiempo_antes, ...
                tiempo_despues, ...
                ventana_basal_ini, ...
                ventana_basal_fin, ...
                duracion_estable, ...
                    k_std, ...
                 umbral_muerte_senal, ...
                duracion_muerte_senal, ...
                  margen_antes_muerte);
                

            if isempty(resultados_metricas)
                resultados_metricas = tabla_metricas_prueba;
            else
                resultados_metricas = [resultados_metricas; tabla_metricas_prueba];
            end

            resumen = addResumen( ...
                resumen, case_id, condition, string(trial), ...
                "OK", "Procesado correctamente");

        catch ME

            fprintf("Error en caso %s | prueba %s: %s\n", ...
                case_id, string(trial), ME.message);

            resumen = addResumen( ...
                resumen, case_id, condition, string(trial), ...
                "ERROR", string(ME.message));
        end
    end
end

%% ============================================================
% GUARDAR EXCEL GLOBAL


out_xlsx = fullfile(output_root, "resumen_metricas_estadistica.xlsx");
out_csv = fullfile(output_root, "resumen_metricas_estadistica.csv");
out_resumen = fullfile(output_root, "resumen_procesamiento.xlsx");

if ~isempty(resultados_metricas)
    writetable(resultados_metricas, out_xlsx, "Sheet", "Resumen_metricas");
    writetable(resultados_metricas, out_csv);
end

writetable(resumen, out_resumen, "FileType", "spreadsheet");

fprintf("\n========================================\n");
fprintf("Proceso terminado.\n");
fprintf("Excel para estadistica guardado en:\n%s\n", out_xlsx);
fprintf("Resumen de procesamiento guardado en:\n%s\n", out_resumen);
fprintf("========================================\n");

%% ============================================================
% FUNCION PRINCIPAL POR PRUEBA


function tabla_metricas_prueba = procesarPruebaCompleta( ...
    isen_file, ...
    delsys_file, ...
    case_id, ...
    condition, ...
    trial, ...
    output_case_folder, ...
    col_tiempo_isen, ...
    isen_cols, ...
    tiempo_antes, ...
    tiempo_despues, ...
    ventana_basal_ini, ...
    ventana_basal_fin, ...
    duracion_estable, ...
          k_std, ...
    umbral_muerte_senal, ...
    duracion_muerte_senal, ...
    margen_antes_muerte)
    %% --------------------------------------------------------
    % CARPETAS DE SALIDA
    %

    folder_graficas = fullfile(output_case_folder, "Graficas");
    folder_csv = fullfile(output_case_folder, "CSV_sincronizados");
   
    if ~exist(folder_graficas, "dir")
        mkdir(folder_graficas);
    end

    if ~exist(folder_csv, "dir")
        mkdir(folder_csv);
    end


    base_file_name = sprintf("%s_%s_prueba_%d", ...
        char(case_id), char(condition), trial);

    %% --------------------------------------------------------
    % LEER ARCHIVOS

    isen = readtable(isen_file, "VariableNamingRule", "preserve");
    delsys = readtable(delsys_file, "VariableNamingRule", "preserve");

    %% --------------------------------------------------------
    % EXTRAER ISEN
    % --------------------------------------------------------

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

    %% --------------------------------------------------------
    % EXTRAER DELSYS
    % ------------
    delsys_data = struct();

    [t_d_head, mag_d_head, idx_head, ~] = extraerAccDelsysPorSensor( ...
        delsys, 9, "Delsys sensor 9 - Cabeza");

    [t_d_10, mag_d_10, idx_10, ~] = extraerAccDelsysPorSensor( ...
        delsys, 10, "Delsys sensor 10");

    [t_d_11, mag_d_11, idx_11, ~] = extraerAccDelsysPorSensor( ...
        delsys, 11, "Delsys sensor 11");

    max_d_10 = max(mag_d_10, [], "omitnan");
    max_d_11 = max(mag_d_11, [], "omitnan");

    fprintf("\n===== ASIGNACION FISICA DELSYS =====\n");
    fprintf("Maximo Delsys sensor 10 = %.4f m/s^2\n", max_d_10);
    fprintf("Maximo Delsys sensor 11 = %.4f m/s^2\n", max_d_11);

    if max_d_10 >= max_d_11

        fprintf("Asignacion: Delsys sensor 10 = PEDAL real\n");
        fprintf("Asignacion: Delsys sensor 11 = VEHICULO real\n");

        t_d_pedal = t_d_10;
        mag_d_pedal = mag_d_10;
        idx_pedal = idx_10;
        sensor_pedal_delsys = "Sensor 10";

        t_d_car = t_d_11;
        mag_d_car = mag_d_11;
        idx_car = idx_11;
        sensor_vehiculo_delsys = "Sensor 11";

    else

        fprintf("Asignacion: Delsys sensor 11 = PEDAL real\n");
        fprintf("Asignacion: Delsys sensor 10 = VEHICULO real\n");

        t_d_pedal = t_d_11;
        mag_d_pedal = mag_d_11;
        idx_pedal = idx_11;
        sensor_pedal_delsys = "Sensor 11";

        t_d_car = t_d_10;
        mag_d_car = mag_d_10;
        idx_car = idx_10;
        sensor_vehiculo_delsys = "Sensor 10";

    end

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

    %% --------------------------------------------------------
    % FRECUENCIAS
 

    fs_isen = estimarFs(isen_data.Pedal.t);
    fs_delsys = estimarFs(delsys_data.Pedal.t);

    fs_common = max(fs_isen, fs_delsys);

    fprintf("\n===== FRECUENCIAS =====\n");
    fprintf("fs iSen   = %.4f Hz\n", fs_isen);
    fprintf("fs Delsys = %.4f Hz\n", fs_delsys);
    fprintf("fs comun  = %.4f Hz\n", fs_common);

    %% --------------------------------------------------------
    % EVENTO DE REFERENCIA: MAXIMO DEL PEDAL REAL
    % --------------------------------------------------------

    [max_pedal_isen, idx_max_pedal_isen] = max(isen_data.Pedal.mag, [], "omitnan");
    [max_pedal_delsys, idx_max_pedal_delsys] = max(delsys_data.Pedal.mag, [], "omitnan");

    tmax_pedal_isen = isen_data.Pedal.t(idx_max_pedal_isen);
    tmax_pedal_delsys = delsys_data.Pedal.t(idx_max_pedal_delsys);

    desfase_pedales_original = tmax_pedal_delsys - tmax_pedal_isen;

    fprintf("\n===== EVENTO DE REFERENCIA =====\n");
    fprintf("Maximo pedal iSen real   = %.4f m/s^2 en t = %.4f s\n", ...
        max_pedal_isen, tmax_pedal_isen);

    fprintf("Maximo pedal Delsys real = %.4f m/s^2 en t = %.4f s\n", ...
        max_pedal_delsys, tmax_pedal_delsys);

    fprintf("Desfase original Delsys - iSen = %.4f s\n", ...
        desfase_pedales_original);

    %% --------------------------------------------------------
    % VENTANA COMUN AUTOMATICA
    % --------------------------------------------------------

    t_rel_isen_pedal    = isen_data.Pedal.t    - tmax_pedal_isen;
    t_rel_isen_vehiculo = isen_data.Vehiculo.t - tmax_pedal_isen;
    t_rel_isen_pecho    = isen_data.Pecho.t    - tmax_pedal_isen;
    t_rel_isen_cabeza   = isen_data.Cabeza.t   - tmax_pedal_isen;

    t_rel_delsys_pedal    = delsys_data.Pedal.t    - tmax_pedal_delsys;
    t_rel_delsys_vehiculo = delsys_data.Vehiculo.t - tmax_pedal_delsys;
    t_rel_delsys_cabeza   = delsys_data.Cabeza.t   - tmax_pedal_delsys;

    inicio_disponible = max([
        min(t_rel_isen_pedal)
        min(t_rel_isen_vehiculo)
        min(t_rel_isen_pecho)
        min(t_rel_isen_cabeza)
        min(t_rel_delsys_pedal)
        min(t_rel_delsys_vehiculo)
        min(t_rel_delsys_cabeza)
    ]);

    fin_disponible = min([
        max(t_rel_isen_pedal)
        max(t_rel_isen_vehiculo)
        max(t_rel_isen_pecho)
        max(t_rel_isen_cabeza)
        max(t_rel_delsys_pedal)
        max(t_rel_delsys_vehiculo)
        max(t_rel_delsys_cabeza)
    ]);

    t_ini_common = max(-tiempo_antes, inicio_disponible);
    t_fin_common = min(tiempo_despues, fin_disponible);

    if t_fin_common <= t_ini_common
        error("No existe una ventana comun valida entre todos los canales.");
    end

    t_common = (t_ini_common : 1/fs_common : t_fin_common)';

    fprintf("\n===== VENTANA COMUN AUTOMATICA =====\n");
    fprintf("Ventana deseada: %.4f a %.4f s\n", -tiempo_antes, tiempo_despues);
    fprintf("Inicio comun disponible: %.4f s\n", inicio_disponible);
    fprintf("Final comun disponible:  %.4f s\n", fin_disponible);
    fprintf("Ventana usada: %.4f a %.4f s\n", t_ini_common, t_fin_common);
    fprintf("Duracion usada: %.4f s\n", t_fin_common - t_ini_common);
    fprintf("Numero de muestras: %d\n", length(t_common));

    %% --------------------------------------------------------
    % INTERPOLAR ISEN
    % --------------------------------------------------------

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

    %% --------------------------------------------------------
    % INTERPOLAR DELSYS
    % --------------------------------------------------------

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


    %% --------------------------------------------------------
% AJUSTAR VENTANA COMUN SI ALGUNA SENAL MUERE
% --------------------------------------------------------
%
% La ventana comun inicial solo considera tiempos disponibles.
% Sin embargo, algunas senales pueden "morir" y quedarse en cero.
% Como cero es un valor numerico valido, hay que detectarlo aparte.
%
% Si cualquier canal cae cerca de cero durante un tiempo sostenido,
% se recorta la ventana comun antes de ese punto para evitar que
% ceros artificiales afecten metricas, graficas o datasets.

t_muerte = NaN(7,1);
nombre_muerte = strings(7,1);

nombre_muerte(1) = "iSen Pedal";
nombre_muerte(2) = "iSen Vehiculo";
nombre_muerte(3) = "iSen Pecho";
nombre_muerte(4) = "iSen Cabeza";
nombre_muerte(5) = "Delsys Pedal";
nombre_muerte(6) = "Delsys Vehiculo";
nombre_muerte(7) = "Delsys Cabeza";

t_muerte(1) = detectarMuerteSenal(t_common, isen_sync.Pedal, fs_common, umbral_muerte_senal, duracion_muerte_senal);
t_muerte(2) = detectarMuerteSenal(t_common, isen_sync.Vehiculo, fs_common, umbral_muerte_senal, duracion_muerte_senal);
t_muerte(3) = detectarMuerteSenal(t_common, isen_sync.Pecho, fs_common, umbral_muerte_senal, duracion_muerte_senal);
t_muerte(4) = detectarMuerteSenal(t_common, isen_sync.Cabeza, fs_common, umbral_muerte_senal, duracion_muerte_senal);
t_muerte(5) = detectarMuerteSenal(t_common, delsys_sync.Pedal, fs_common, umbral_muerte_senal, duracion_muerte_senal);
t_muerte(6) = detectarMuerteSenal(t_common, delsys_sync.Vehiculo, fs_common, umbral_muerte_senal, duracion_muerte_senal);
t_muerte(7) = detectarMuerteSenal(t_common, delsys_sync.Cabeza, fs_common, umbral_muerte_senal, duracion_muerte_senal);

idx_muerte = find(isfinite(t_muerte));

if ~isempty(idx_muerte)

    [t_muerte_min, idx_min_local] = min(t_muerte(idx_muerte));
    idx_canal_muerte = idx_muerte(idx_min_local);

    fprintf("\n===== MUERTE DE SENAL DETECTADA =====\n");
    fprintf("Canal: %s\n", nombre_muerte(idx_canal_muerte));
    fprintf("Tiempo de muerte detectado: %.4f s\n", t_muerte_min);

    t_fin_antes_muerte = t_muerte_min - margen_antes_muerte;

    if t_fin_antes_muerte < t_fin_common
        fprintf("Ventana comun antes de ajuste: %.4f a %.4f s\n", t_ini_common, t_fin_common);

        t_fin_common = t_fin_antes_muerte;

        if t_fin_common <= t_ini_common
            error("La senal muere antes de completar una ventana comun valida.");
        end

        mask_recorte = t_common <= t_fin_common;

        t_common = t_common(mask_recorte);

        isen_sync.Pedal    = isen_sync.Pedal(mask_recorte);
        isen_sync.Vehiculo = isen_sync.Vehiculo(mask_recorte);
        isen_sync.Pecho    = isen_sync.Pecho(mask_recorte);
        isen_sync.Cabeza   = isen_sync.Cabeza(mask_recorte);

        delsys_sync.Pedal    = delsys_sync.Pedal(mask_recorte);
        delsys_sync.Vehiculo = delsys_sync.Vehiculo(mask_recorte);
        delsys_sync.Cabeza   = delsys_sync.Cabeza(mask_recorte);

        fprintf("Ventana comun despues de ajuste: %.4f a %.4f s\n", t_ini_common, t_fin_common);
        fprintf("Numero de muestras despues de ajuste: %d\n", length(t_common));
    end
end

    %% --------------------------------------------------------
    % DETECTAR ESTABILIZACION PARA GRAFICAS
    % --------------------------------------------------------

    [t_est_isen_pedal, ~, ~, ~, ~] = detectarEstabilizacion( ...
        t_common, isen_sync.Pedal, ...
        ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common);

    [t_est_isen_vehiculo, ~, ~, ~, ~] = detectarEstabilizacion( ...
        t_common, isen_sync.Vehiculo, ...
        ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common);

    [t_est_isen_cabeza, ~, ~, ~, ~] = detectarEstabilizacion( ...
        t_common, isen_sync.Cabeza, ...
        ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common);

    [t_est_isen_pecho, ~, ~, ~, ~] = detectarEstabilizacion( ...
        t_common, isen_sync.Pecho, ...
        ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common);

    [t_est_delsys_pedal, ~, ~, ~, ~] = detectarEstabilizacion( ...
        t_common, delsys_sync.Pedal, ...
        ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common);

    [t_est_delsys_vehiculo, ~, ~, ~, ~] = detectarEstabilizacion( ...
        t_common, delsys_sync.Vehiculo, ...
        ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common);

    [t_est_delsys_cabeza, ~, ~, ~, ~] = detectarEstabilizacion( ...
        t_common, delsys_sync.Cabeza, ...
        ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common);

    %% --------------------------------------------------------
    % DATASET SINCRONIZADO
    % --------------------------------------------------------

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
            'iSen_Pedal_real_J_ms2', ...
            'iSen_Vehiculo_real_K_ms2', ...
            'iSen_Pecho_B_ms2', ...
            'iSen_Cabeza_A_ms2', ...
            'Delsys_Pedal_real_ms2', ...
            'Delsys_Vehiculo_real_ms2', ...
            'Delsys_Cabeza_sensor9_ms2' ...
        } ...
    );

    out_csv_dataset = fullfile(folder_csv, ...
        base_file_name + "_dataset_sincronizado.csv");

    writetable(dataset_prueba, out_csv_dataset);

    %% --------------------------------------------------------
    % GRAFICAS
    % --------------------------------------------------------

    out_fig_all = fullfile(folder_graficas, ...
        base_file_name + "_01_todas_las_senales.png");

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
        "DisplayName", "iSen Vehiculo real");

    plot(t_common, delsys_sync.Vehiculo, ...
        "LineWidth", 1.1, ...
        "DisplayName", "Delsys Vehiculo real " + delsys_data.Vehiculo.sensor);

    plot(t_common, isen_sync.Cabeza, ...
        "LineWidth", 1.1, ...
        "DisplayName", "iSen Cabeza A");

    plot(t_common, delsys_sync.Cabeza, ...
        "LineWidth", 1.1, ...
        "DisplayName", "Delsys Cabeza Sensor 9");

    plot(t_common, isen_sync.Pecho, ...
        "LineWidth", 1.1, ...
        "DisplayName", "iSen Pecho B");

    xline(0, "--", "Maximo pedal", ...
        "LabelOrientation", "aligned", ...
        "HandleVisibility", "off");

    grid on;
    box on;
    legend("Location", "best");

    xlabel("Tiempo relativo al maximo del pedal [s]");
    ylabel("Magnitud de aceleracion [m/s^2]");

    title(sprintf("%s %s - Prueba %d - Todas las senales sincronizadas", ...
        case_id, condition, trial));

    subtitle(sprintf( ...
        "Ventana %.2f a %.2f s | fs comun = %.2f Hz", ...
        t_ini_common, t_fin_common, fs_common));

    exportgraphics(fig_all, out_fig_all, "Resolution", 200);
    close(fig_all);

    out_fig_pedal = fullfile(folder_graficas, ...
        base_file_name + "_02_pedal_estabilizacion.png");

    graficarParEstabilizacion( ...
        t_common, ...
        isen_sync.Pedal, ...
        delsys_sync.Pedal, ...
        "iSen Pedal", ...
        "Delsys Pedal", ...
        t_est_isen_pedal, ...
        t_est_delsys_pedal, ...
        "Pedal sincronizado - iSen vs Delsys", ...
        out_fig_pedal);

    out_fig_vehiculo = fullfile(folder_graficas, ...
        base_file_name + "_03_vehiculo_estabilizacion.png");

    graficarParEstabilizacion( ...
        t_common, ...
        isen_sync.Vehiculo, ...
        delsys_sync.Vehiculo, ...
        "iSen Vehiculo", ...
        "Delsys Vehiculo", ...
        t_est_isen_vehiculo, ...
        t_est_delsys_vehiculo, ...
        "Vehiculo sincronizado - iSen vs Delsys", ...
        out_fig_vehiculo);

    out_fig_cabeza = fullfile(folder_graficas, ...
        base_file_name + "_04_cabeza_estabilizacion.png");

    graficarParEstabilizacion( ...
        t_common, ...
        isen_sync.Cabeza, ...
        delsys_sync.Cabeza, ...
        "iSen Cabeza", ...
        "Delsys Cabeza", ...
        t_est_isen_cabeza, ...
        t_est_delsys_cabeza, ...
        "Cabeza sincronizada - iSen vs Delsys", ...
        out_fig_cabeza);

    out_fig_pecho = fullfile(folder_graficas, ...
        base_file_name + "_05_pecho_estabilizacion.png");

    graficarUnaSenalEstabilizacion( ...
        t_common, ...
        isen_sync.Pecho, ...
        "iSen Pecho", ...
        t_est_isen_pecho, ...
        "Pecho sincronizado - iSen", ...
        out_fig_pecho);

    %% --------------------------------------------------------
    % METRICAS PARA ANALISIS ESTADISTICO
    % --------------------------------------------------------

    tabla_metricas_prueba = table();

    tabla_metricas_prueba = [tabla_metricas_prueba; calcularMetricasSensor( ...
        case_id, condition, trial, ...
        "iSen", "Pedal real J", ...
        t_common, isen_sync.Pedal, ...
        ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common, ...
        t_ini_common, t_fin_common, ...
        isen_file, delsys_file, ...
        out_csv_dataset, out_fig_all, out_fig_pedal, out_fig_vehiculo, out_fig_cabeza, out_fig_pecho)];

    tabla_metricas_prueba = [tabla_metricas_prueba; calcularMetricasSensor( ...
        case_id, condition, trial, ...
        "iSen", "Vehiculo real K", ...
        t_common, isen_sync.Vehiculo, ...
        ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common, ...
        t_ini_common, t_fin_common, ...
        isen_file, delsys_file, ...
        out_csv_dataset, out_fig_all, out_fig_pedal, out_fig_vehiculo, out_fig_cabeza, out_fig_pecho)];

    tabla_metricas_prueba = [tabla_metricas_prueba; calcularMetricasSensor( ...
        case_id, condition, trial, ...
        "iSen", "Pecho B", ...
        t_common, isen_sync.Pecho, ...
        ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common, ...
        t_ini_common, t_fin_common, ...
        isen_file, delsys_file, ...
        out_csv_dataset, out_fig_all, out_fig_pedal, out_fig_vehiculo, out_fig_cabeza, out_fig_pecho)];

    tabla_metricas_prueba = [tabla_metricas_prueba; calcularMetricasSensor( ...
        case_id, condition, trial, ...
        "iSen", "Cabeza A", ...
        t_common, isen_sync.Cabeza, ...
        ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common, ...
        t_ini_common, t_fin_common, ...
        isen_file, delsys_file, ...
        out_csv_dataset, out_fig_all, out_fig_pedal, out_fig_vehiculo, out_fig_cabeza, out_fig_pecho)];

    tabla_metricas_prueba = [tabla_metricas_prueba; calcularMetricasSensor( ...
        case_id, condition, trial, ...
        "Delsys", "Pedal real " + delsys_data.Pedal.sensor, ...
        t_common, delsys_sync.Pedal, ...
        ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common, ...
        t_ini_common, t_fin_common, ...
        isen_file, delsys_file, ...
        out_csv_dataset, out_fig_all, out_fig_pedal, out_fig_vehiculo, out_fig_cabeza, out_fig_pecho)];

    tabla_metricas_prueba = [tabla_metricas_prueba; calcularMetricasSensor( ...
        case_id, condition, trial, ...
        "Delsys", "Vehiculo real " + delsys_data.Vehiculo.sensor, ...
        t_common, delsys_sync.Vehiculo, ...
        ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common, ...
        t_ini_common, t_fin_common, ...
        isen_file, delsys_file, ...
        out_csv_dataset, out_fig_all, out_fig_pedal, out_fig_vehiculo, out_fig_cabeza, out_fig_pecho)];

    tabla_metricas_prueba = [tabla_metricas_prueba; calcularMetricasSensor( ...
        case_id, condition, trial, ...
        "Delsys", "Cabeza Sensor 9", ...
        t_common, delsys_sync.Cabeza, ...
        ventana_basal_ini, ventana_basal_fin, duracion_estable, k_std, fs_common, ...
        t_ini_common, t_fin_common, ...
        isen_file, delsys_file, ...
        out_csv_dataset, out_fig_all, out_fig_pedal, out_fig_vehiculo, out_fig_cabeza, out_fig_pecho)];

    %% --------------------------------------------------------
    % EXCEL POR PRUEBA
    % --------------------------------------------------------

%% --------------------------------------------------------
% FIN DE PROCESAMIENTO DE LA PRUEBA
% --------------------------------------------------------

fprintf("\nPrueba procesada correctamente: %s\n", base_file_name);

end
%% ============================================================
% FUNCIONES AUXILIARES
% ============================================================

function fila = calcularMetricasSensor( ...
    case_id, condition, trial, sistema, sensor, ...
    t, senal, ...
    basal_ini, basal_fin, duracion_estable, k_std, fs_common, ...
    t_ini_common, t_fin_common, ...
    archivo_isen, archivo_delsys, ...
    csv_sincronizado, fig_general, fig_pedal, fig_vehiculo, fig_cabeza, fig_pecho)

    %% Maximo y tiempo relativo al pedal
    [max_val, idx_max] = max(senal, [], "omitnan");
    t_max_relativo = t(idx_max);

    %% Estabilizacion
    [t_estable, base, desv, lim_inf, lim_sup, t_inicio_busqueda] = detectarEstabilizacion( ...
        t, senal, basal_ini, basal_fin, duracion_estable, k_std, fs_common);

    %% Rango pico-basal
    rango_pico_basal = max_val - base;

    %% RMS y area post-evento respecto al basal
    mask_post = t >= 0 & t <= t_fin_common & isfinite(senal);

    if sum(mask_post) < 3 || isnan(base)
        rms_post = NaN;
        area_post = NaN;
    else
        t_post = t(mask_post);
        senal_post = senal(mask_post);

        rms_post = sqrt(mean((senal_post - base).^2, "omitnan"));
        area_post = trapz(t_post, abs(senal_post - base));
    end

    %% Nombres cortos de archivos
    [~, name_isen, ext_isen] = fileparts(archivo_isen);
    [~, name_delsys, ext_delsys] = fileparts(archivo_delsys);

    archivo_isen_short = string(name_isen) + string(ext_isen);
    archivo_delsys_short = string(name_delsys) + string(ext_delsys);

    %% Fila final
    fila = table( ...
        string(case_id), ...
        string(condition), ...
        trial, ...
        string(sistema), ...
        string(sensor), ...
        max_val, ...
        t_max_relativo, ...
        base, ...
        desv, ...
        lim_inf, ...
        lim_sup, ...
        rango_pico_basal, ...
        t_inicio_busqueda, ...
        t_estable, ...
        rms_post, ...
        area_post, ...
        t_ini_common, ...
        t_fin_common, ...
        fs_common, ...
        length(t), ...
        archivo_isen_short, ...
        archivo_delsys_short, ...
        string(csv_sincronizado), ...
        string(fig_general), ...
        string(fig_pedal), ...
        string(fig_vehiculo), ...
        string(fig_cabeza), ...
        string(fig_pecho), ...
        'VariableNames', { ...
            'Caso', ...
            'Condicion', ...
            'Prueba', ...
            'Sistema', ...
            'Sensor', ...
            'Maximo_ms2', ...
            'Tiempo_Maximo_Relativo_Pedal_s', ...
            'Media_Basal_ms2', ...
            'STD_Basal_ms2', ...
            'Limite_Inferior_ms2', ...
            'Limite_Superior_ms2', ...
            'Rango_Pico_Basal_ms2', ...
            'Tiempo_Inicio_Busqueda_s', ...
            'Tiempo_Estabilizacion_s', ...
            'RMS_PostEvento_ms2', ...
            'Area_PostEvento_ms2_s', ...
            'Ventana_Inicio_s', ...
            'Ventana_Fin_s', ...
            'Frecuencia_Comun_Hz', ...
            'Num_Muestras', ...
            'Archivo_iSen', ...
            'Archivo_Delsys', ...
            'CSV_Sincronizado', ...
            'Grafica_General', ...
            'Grafica_Pedal', ...
            'Grafica_Vehiculo', ...
            'Grafica_Cabeza', ...
            'Grafica_Pecho' ...
        } ...
    );
end

function [t_estable, base, desv, lim_inf, lim_sup, t_inicio_busqueda] = detectarEstabilizacion( ...
    t, senal, basal_ini, basal_fin, duracion_estable, k_std, fs)

    t_estable = NaN;
    t_inicio_busqueda = NaN;

    %% 1) Calcular basal antes del pedal
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

    %% 2) Buscar maximo propio de la senal despues del pedal
    idx_despues_pedal = find(t >= 0 & isfinite(senal));

    if isempty(idx_despues_pedal)
        return;
    end

    [~, idx_max_local] = max(senal(idx_despues_pedal), [], "omitnan");

    idx_max_senal = idx_despues_pedal(idx_max_local);

    t_inicio_busqueda = t(idx_max_senal);

    %% 3) Buscar estabilizacion despues del maximo propio
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

function graficarParEstabilizacion( ...
    t, y1, y2, label1, label2, t_est1, t_est2, titulo, out_fig)

    fig = figure("Visible", "off");
    fig.Position = [100 100 1400 750];

    plot(t, y1, ...
        "LineWidth", 1.4, ...
        "DisplayName", label1);
    hold on;

    plot(t, y2, ...
        "LineWidth", 1.4, ...
        "DisplayName", label2);

    xline(0, "--", "Maximo pedal", ...
        "HandleVisibility", "off");

    if ~isnan(t_est1)
        xline(t_est1, ":", ...
            sprintf("Est. %s %.2f s", label1, t_est1), ...
            "HandleVisibility", "off");

        y_est = interp1(t, y1, t_est1, "linear", NaN);
        plot(t_est1, y_est, "o", "HandleVisibility", "off");
    end

    if ~isnan(t_est2)
        xline(t_est2, ":", ...
            sprintf("Est. %s %.2f s", label2, t_est2), ...
            "HandleVisibility", "off");

        y_est = interp1(t, y2, t_est2, "linear", NaN);
        plot(t_est2, y_est, "o", "HandleVisibility", "off");
    end

    grid on;
    box on;
    legend("Location", "best");

    xlabel("Tiempo relativo al maximo del pedal [s]");
    ylabel("Magnitud de aceleracion [m/s^2]");

    title(titulo);
    subtitle("Se muestran tiempos de estabilizacion");

    exportgraphics(fig, out_fig, "Resolution", 200);
    close(fig);
end

function graficarUnaSenalEstabilizacion( ...
    t, y, label1, t_est1, titulo, out_fig)

    fig = figure("Visible", "off");
    fig.Position = [100 100 1400 750];

    plot(t, y, ...
        "LineWidth", 1.4, ...
        "DisplayName", label1);
    hold on;

    xline(0, "--", "Maximo pedal", ...
        "HandleVisibility", "off");

    if ~isnan(t_est1)
        xline(t_est1, ":", ...
            sprintf("Est. %s %.2f s", label1, t_est1), ...
            "HandleVisibility", "off");

        y_est = interp1(t, y, t_est1, "linear", NaN);
        plot(t_est1, y_est, "o", "HandleVisibility", "off");
    end

    grid on;
    box on;
    legend("Location", "best");

    xlabel("Tiempo relativo al maximo del pedal [s]");
    ylabel("Magnitud de aceleracion [m/s^2]");

    title(titulo);
    subtitle("Se muestra tiempo de estabilizacion");

    exportgraphics(fig, out_fig, "Resolution", 200);
    close(fig);
end

function [t, mag, idxs, names_d] = extraerAccDelsysPorSensor(delsys, sensor_num, nombre_sensor)

    names_d = string(delsys.Properties.VariableNames);
    names_upper = upper(names_d);

    sensor_num_str = string(sensor_num);
    patron_sensor = "SENSOR " + sensor_num_str;

    idx_ax = find(contains(names_upper, patron_sensor) & contains(names_upper, "ACC.X"), 1);
    idx_ay = find(contains(names_upper, patron_sensor) & contains(names_upper, "ACC.Y"), 1);
    idx_az = find(contains(names_upper, patron_sensor) & contains(names_upper, "ACC.Z"), 1);

    if isempty(idx_ax) || isempty(idx_ay) || isempty(idx_az)

        idx_ax = find(contains(names_upper, "ACC.X") & contains(names_upper, sensor_num_str), 1);
        idx_ay = find(contains(names_upper, "ACC.Y") & contains(names_upper, sensor_num_str), 1);
        idx_az = find(contains(names_upper, "ACC.Z") & contains(names_upper, sensor_num_str), 1);
    end

    if isempty(idx_ax) || isempty(idx_ay) || isempty(idx_az)

        disp("Columnas Delsys disponibles:");
        disp(names_d');

        error("No encontre ACC.X/Y/Z para %s.", nombre_sensor);
    end

    %% Buscar columna de tiempo cercana
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
    fprintf("Maximo: %.4f m/s^2\n", max(mag, [], "omitnan"));
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

function files = listarArchivosDatos(folderPath)

    files_csv = dir(fullfile(folderPath, "*.csv"));
    files_xlsx = dir(fullfile(folderPath, "*.xlsx"));
    files_xls = dir(fullfile(folderPath, "*.xls"));

    files = [files_csv; files_xlsx; files_xls];

    keep = true(length(files), 1);

    for i = 1:length(files)
        if startsWith(string(files(i).name), "~$")
            keep(i) = false;
        end
    end

    files = files(keep);
end

function [trial_num, condition] = extraerInfoISen(file_name)

    name = upper(string(file_name));

    trial_num = NaN;
    condition = "";

    if contains(name, "CA")
        condition = "CA";
    elseif contains(name, "SA")
        condition = "SA";
    else
        condition = "NA";
    end

    tokens = regexp(name, '(CA|SA)[\-_]?0?(\d+)', 'tokens');

    if ~isempty(tokens)
        trial_num = str2double(tokens{1}{2});
        return;
    end

    nums = regexp(name, '\d+', 'match');

    if ~isempty(nums)
        trial_num = str2double(nums{end});
    end
end

function trial_num = extraerEnsayoDelsys(file_name)

    name = upper(string(file_name));

    trial_num = NaN;

    tokens = regexp(name, 'ENSAYO[\-_ ]?(\d+)', 'tokens');

    if ~isempty(tokens)
        trial_num = str2double(tokens{1}{1});
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

    error("Tipo de dato no reconocido para conversion numerica.");
end

function resumen = addResumen(resumen, case_id, condition, trial, status, message)

    newRow = table( ...
        string(case_id), ...
        string(condition), ...
        string(trial), ...
        string(status), ...
        string(message), ...
        'VariableNames', {'Caso', 'Condicion', 'Prueba', 'Estado', 'Mensaje'} ...
    );

    resumen = [resumen; newRow];
end

function t_muerte = detectarMuerteSenal(t, senal, fs, umbral_muerte, duracion_muerte)

    t_muerte = NaN;

    if isempty(t) || isempty(senal) || isnan(fs) || fs <= 0
        return;
    end

    % Se considera senal muerta si permanece cerca de cero
    % durante duracion_muerte segundos consecutivos.
    cerca_cero = abs(senal) <= umbral_muerte & isfinite(senal);

    n_consecutivos = max(3, round(duracion_muerte * fs));

    if length(cerca_cero) < n_consecutivos
        return;
    end

    % Buscar el primer tramo sostenido cerca de cero.
    for k = 1:length(cerca_cero) - n_consecutivos + 1

        idx_ini = k;
        idx_fin = k + n_consecutivos - 1;

        if all(cerca_cero(idx_ini:idx_fin))
            t_muerte = t(idx_ini);
            return;
        end
    end
end