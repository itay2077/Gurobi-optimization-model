function run_sensitivities(which, mode)
% RUN_SENSITIVITIES  Run the sensitivity analyses of the paper (Methods 2.4, spec v2).
%
%   run_sensitivities('base', 'dry')  % print what would run (no solving, no files written)
%   run_sensitivities('base')         % D1, A15, B06, B025, B0 - Excel switches OFF   (33 runs)
%   run_sensitivities('D2')           % data centres - Excel 'Read Me'!B2 = 1           (6 runs)
%   run_sensitivities('S')            % storage cost x1.5 - Excel 'Read Me'!B3 = 1.5 (4 runs)
%   run_sensitivities({'D1','B0'})    % any subset of setting ids
%
% Every setting is run in two phases, each as its own OPT_ONE_SENS run:
%   1) cost   : least-cost run per land cap  -> C* (TotalCost_AllYears)
%   2) emis   : emission-min with budgets = factor x C* (rounded UP to 0.01 bn NIS),
%               selected per land cap with TEST_CELLS
% After each phase yearly_export is run on the new run folder.
%
% Settings are passed to OPT_ONE_SENS through run_overrides.m (written here and
% always deleted afterwards). Progress is logged in <runsRoot>\OPT_ONE_SENS\sens_log.csv;
% phases already logged as 'done' are skipped, so the function can simply be called
% again after an interruption. A combined table is written to sens_summary.csv.
%
% Before the first automated run: answer the registry question once by hand
% (the Excel changed since V4 was fingerprinted) - see the notes in the chat.

    if nargin < 1 || isempty(which), which = 'base'; end
    if nargin < 2 || isempty(mode),  mode  = 'run';  end
    dry = strcmpi(mode, 'dry');

    codeDir = fileparts(mfilename('fullpath'));
    addpath(codeDir);
    MP      = machine_paths();
    regRoot = fullfile(MP.runsRoot, 'OPT_ONE_SENS');
    logFile = fullfile(regRoot, 'sens_log.csv');
    sumFile = fullfile(regRoot, 'sens_summary.csv');
    ptrFile = fullfile(regRoot, 'latest', 'pointer.txt');
    ovrFile = fullfile(codeDir, 'run_overrides.m');

    if isfile(ovrFile)
        error(['run_overrides.m already exists in %s (left from an interrupted run?). ' ...
               'Check it and delete it before continuing.'], codeDir);
    end

    S = settings_table();
    S = select_settings(S, which);
    fprintf('\n===== run_sensitivities (%s, %s) : %d settings =====\n', ...
        strjoin(cellstr(string(which)), ','), mode, numel(S));

    % ---- Excel switch state must match every selected setting ----
    [dcSwitch, battMult] = read_excel_switches(MP.xlsFile);
    fprintf('Excel switches: DC (''Read Me''!B2) = %g, battery capex multiplier (''Read Me''!B3) = %g\n', dcSwitch, battMult);
    for k = 1:numel(S)
        [okX, need] = excel_ok(S(k).excel, dcSwitch, battMult);
        if ~okX && dry
            fprintf('  %s: needs Excel state "%s" (%s) - NOT the current state\n', S(k).id, S(k).excel, need);
        elseif ~okX
            error('Setting %s needs the Excel in state "%s" (%s). Set it, save the Excel, and call again.', ...
                S(k).id, S(k).excel, need);
        end
    end

    L = read_log(logFile);

    for k = 1:numel(S)
        s = S(k);
        fprintf('\n----- %s : %s -----\n', s.id, s.desc);

        % ===== phase 1: least cost =====
        costLines = [common_lines(s), { ...
            'OBJECTIVE = ''cost'';', ...
            sprintf('areaList = %s;', mat2str(s.areas)), ...
            'TEST_CELLS = [];', ...
            sprintf('RUN_TAG = ''sens_%s_cost'';', s.id), ...
            sprintf('RUN_DESCRIPTION = ''Sensitivity %s (%s): least cost per land cap'';', s.id, s.desc)}];
        costDir = logged_dir(L, s.id, 'cost');
        if dry
            print_lines('cost phase overrides', costLines);
        elseif isempty(costDir)
            costDir = run_phase(costLines, codeDir, ovrFile, ptrFile, logFile, s.id, 'cost');
            L = read_log(logFile);
        else
            fprintf('cost phase already done: %s\n', costDir);
        end

        % ===== phase 2: emission-min at factor x C* =====
        if dry
            fprintf('emis phase: budgets = ceil(f x C*(A) / 0.01 bn) for f = %s and A = %s (%d scenarios)\n', ...
                mat2str(s.factors), mat2str(s.areas), numel(s.factors) * numel(s.areas));
            continue
        end
        if ~isempty(logged_dir(L, s.id, 'emis'))
            fprintf('emis phase already done: %s\n', logged_dir(L, s.id, 'emis'));
            continue
        end
        Kc = read_kpi(costDir);
        TC = zeros(0, 2);  B = [];
        for A = s.areas
            r = find(Kc.MaxAreaSolar == A, 1);
            if isempty(r) || ~strcmpi(string(Kc.ResultStatus(r)), "OPTIMAL")
                warning('No OPTIMAL least-cost result for %s at %g km2 - skipped in the emis phase.', s.id, A);
                continue
            end
            Cstar = Kc.TotalCost_AllYears(r);
            for f = s.factors
                b = ceil(f * Cstar / 1e7) * 1e7;          % NIS, rounded up to 0.01 bn
                B(end+1) = b;  TC(end+1, :) = [b / 1e9, A]; %#ok<AGROW>
            end
        end
        if isempty(TC)
            warning('Nothing to run in the emis phase of %s.', s.id);
            continue
        end
        emisLines = [common_lines(s), { ...
            'OBJECTIVE = ''emissions'';', ...
            sprintf('areaList = %s;', mat2str(s.areas)), ...
            sprintf('budgetList = %s;', mat2str(unique(B), 15)), ...
            sprintf('TEST_CELLS = %s;', mat2str(TC, 15)), ...
            'SKIP_INFEASIBLE_BUDGETS = false;   % budgets are >= C* by construction', ...
            sprintf('RUN_TAG = ''sens_%s_emis'';', s.id), ...
            sprintf('RUN_DESCRIPTION = ''Sensitivity %s (%s): emission-min at %s x least cost'';', s.id, s.desc, mat2str(s.factors))}];
        emisDir = run_phase(emisLines, codeDir, ovrFile, ptrFile, logFile, s.id, 'emis');
        L = read_log(logFile);

        append_summary(sumFile, s, costDir, emisDir, s.factors);
    end
    fprintf('\n===== run_sensitivities finished =====\nLog: %s\nSummary: %s\n', logFile, sumFile);
end

%% ===================== settings (Methods 2.4, spec v2) =====================
function S = settings_table()
    S = struct('id', {}, 'desc', {}, 'excel', {}, 'areas', {}, 'factors', {}, 'lines', {});
    S(end+1) = mk('D1',   'high demand (Noga 2026 high, 3.84%/yr)', 'base', [400 600 1000], 1.05, ...
                  {'DEMAND_PATH = ''noga2026_high'';'});
    S(end+1) = mk('D2',   'data centres 2 GW 2027 -> 3 GW 2030 -> 4.2 GW 2050 (Excel)', 'DC', [400 600 1000], 1.05, {});
    S(end+1) = mk('A15',  'deployment rate 2x Table 2', 'base', [400 600 1000], [1.025 1.05 1.10 1.20], ...
                  {'RAMP_SCHEDULE.solar = [2025 4.5; 2030 6.0; 2035 7.5; 2040 10.5; 2050 13.5];', ...
                   'RAMP_SCHEDULE.batt  = [2025 3.0; 2030 6.0; 2035 6.0; 2040 7.5; 2050 9.0];'});
    S(end+1) = mk('B06',  'storage capacity credit beta = 0.6',  'base', [400 1000], 1.05, ...
                  {'ENABLE_BETA_SWEEP = true;', 'betaList_onEnabled = [0.6];'});
    S(end+1) = mk('B025', 'storage capacity credit beta = 0.25', 'base', [400 1000], 1.05, ...
                  {'ENABLE_BETA_SWEEP = true;', 'betaList_onEnabled = [0.25];'});
    S(end+1) = mk('B0',   'storage capacity credit beta = 0',    'base', [400 1000], 1.05, ...
                  {'ENABLE_BETA_SWEEP = true;', 'betaList_onEnabled = [0];'});
    S(end+1) = mk('S',    'storage capital cost x1.5 (Excel)', 'S', [400 1000], 1.05, {});
end

function s = mk(id, desc, excel, areas, factors, lines)
    s = struct('id', id, 'desc', desc, 'excel', excel, 'areas', areas, 'factors', factors, 'lines', {lines});
end

function S = select_settings(S, which)
    ids = {S.id};
    if ischar(which) || isstring(which)
        w = char(which);
        switch upper(w)
            case 'BASE', pick = strcmp({S.excel}, 'base');
            case 'ALL',  pick = true(size(S));            % dry runs only make sense here
            otherwise,   pick = strcmpi(ids, w);
        end
    else
        pick = ismember(lower(ids), lower(cellstr(which)));
    end
    if ~any(pick), error('No setting matches "%s". Ids: %s', strjoin(cellstr(string(which)), ','), strjoin(ids, ', ')); end
    S = S(pick);
end

function c = common_lines(s)
    % every run: no nuclear, no RE target, beta = 1 unless the setting overrides it,
    % automated folder creation, data-variant flag for Excel-switch settings
    c = [{'ENABLE_NUCLEAR = false;', 'RE_TARGET_2050 = 0;', ...
          'ENABLE_BETA_SWEEP = true;', 'betaList_onEnabled = [1];', ...
          'AUTO_NEW_RUN = true;', ...
          sprintf('SENS_DATA_VARIANT = %s;', tf(~strcmp(s.excel, 'base')))}, s.lines];
end

%% ===================== running one phase =====================
function outDir = run_phase(lines, codeDir, ovrFile, ptrFile, logFile, id, phase)
    oldPtr = '';
    if isfile(ptrFile), oldPtr = strtrim(fileread(ptrFile)); end
    fid = fopen(ovrFile, 'w', 'n', 'UTF-8');
    fprintf(fid, '%% run_overrides.m - written by run_sensitivities (%s, %s). Deleted after the run.\n', id, phase);
    fprintf(fid, '%s\n', lines{:});
    fclose(fid);
    cleanup = onCleanup(@() delete_if(ovrFile)); %#ok<NASGU>
    t0 = tic;  status = 'done';  note = '';  outDir = '';
    try
        % OPT_ONE_SENS starts with "clear": run it in the base workspace so that
        % the variables of this function are not cleared
        evalin('base', sprintf('run(''%s'');', strrep(fullfile(codeDir, 'OPT_ONE_SENS.m'), '''', '''''')));
        newPtr = strtrim(fileread(ptrFile));
        if strcmp(newPtr, oldPtr)
            error('The run pointer did not change - no new run folder was created.');
        end
        outDir = newPtr;
        if exist('yearly_export', 'file')
            yearly_export(outDir);
        else
            warning('yearly_export.m not found - yearly_summary.csv not written for %s.', outDir);
        end
    catch ME
        status = 'error';  note = ME.message;
        fprintf(2, '\n[run_sensitivities] %s %s failed: %s\n', id, phase, ME.message);
    end
    clear cleanup                                   % deletes run_overrides.m
    write_log(logFile, id, phase, status, outDir, toc(t0) / 60, note);
    if strcmp(status, 'error')
        error('Stopped at %s %s (see the log). Fix the cause and call run_sensitivities again; finished phases are skipped.', id, phase);
    end
end

%% ===================== Excel switches =====================
function [dc, mult] = read_excel_switches(xls)
    dc   = readmatrix(xls, 'Sheet', 'Read Me', 'Range', 'B2:B2');
    mult = readmatrix(xls, 'Sheet', 'Read Me', 'Range', 'B3:B3');
    if isempty(dc) || isnan(dc),     error('Could not read the DC switch (''Read Me''!B2) from %s', xls); end
    if isempty(mult) || isnan(mult), error('Could not read the battery capex multiplier (''Read Me''!B3) from %s', xls); end
end

function [ok, need] = excel_ok(state, dc, mult)
    switch state
        case 'base', ok = dc == 0 && mult == 1;   need = 'Read Me B2 = 0 and B3 = 1';
        case 'DC',   ok = dc == 1 && mult == 1;   need = 'Read Me B2 = 1 and B3 = 1';
        case 'S',    ok = dc == 0 && mult == 1.5; need = 'Read Me B2 = 0 and B3 = 1.5';
        otherwise,   ok = false;                  need = 'unknown state';
    end
end

%% ===================== log and summary =====================
function L = read_log(f)
    if isfile(f)
        L = readtable(f, 'TextType', 'string', 'Delimiter', ',');
    else
        L = table(string.empty(0,1), string.empty(0,1), string.empty(0,1), string.empty(0,1), zeros(0,1), string.empty(0,1), string.empty(0,1), ...
            'VariableNames', {'setting','phase','status','outDir','minutes','time','note'});
    end
end

function d = logged_dir(L, id, phase)
    d = '';
    if isempty(L), return; end
    r = find(L.setting == id & L.phase == phase & L.status == "done", 1, 'last');
    if ~isempty(r), d = char(L.outDir(r)); end
end

function write_log(f, id, phase, status, outDir, minutes, note)
    newFile = ~isfile(f);
    fid = fopen(f, 'a', 'n', 'UTF-8');
    if newFile, fprintf(fid, 'setting,phase,status,outDir,minutes,time,note\n'); end
    fprintf(fid, '%s,%s,%s,"%s",%.1f,%s,"%s"\n', id, phase, status, outDir, minutes, ...
        char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')), strrep(note, '"', ''''));
    fclose(fid);
end

function K = read_kpi(runDir)
    f = fullfile(runDir, 'tables', 'KPI_summary.csv');
    if ~isfile(f), error('KPI_summary.csv not found in %s', runDir); end
    K = readtable(f, 'TextType', 'string');
end

function append_summary(sumFile, s, costDir, emisDir, factors)
    Kc = read_kpi(costDir);  Ke = read_kpi(emisDir);
    keep = {'MaxAreaSolar','MaxCost','ResultStatus','TotalCost_AllYears','TotalEmissions_AllYears', ...
            'RenewablesPct2050','Cap2050_Solar','Cap2050_Gas','Cap2050_Battery','SolarLand_km2', ...
            'Dual_Land_Sum','Dual_Budget','LandFullYear','BetaX','Runtime_hrs'};
    rows = table();
    for A = s.areas
        rc = find(Kc.MaxAreaSolar == A, 1);
        if isempty(rc), continue; end
        Cstar = Kc.TotalCost_AllYears(rc);
        t = Kc(rc, intersect(keep, Kc.Properties.VariableNames, 'stable'));
        t.setting = string(s.id); t.phase = "cost"; t.factor = 1; t.Cstar = Cstar;
        rows = [rows; t]; %#ok<AGROW>
        for f = factors
            b  = ceil(f * Cstar / 1e7) * 1e7;
            re = find(Ke.MaxAreaSolar == A & abs(Ke.MaxCost - b) < 1, 1);
            if isempty(re), continue; end
            t = Ke(re, intersect(keep, Ke.Properties.VariableNames, 'stable'));
            t.setting = string(s.id); t.phase = "emis"; t.factor = f; t.Cstar = Cstar;
            rows = [rows; t]; %#ok<AGROW>
        end
    end
    if isempty(rows), return; end
    rows = movevars(rows, {'setting','phase','factor','Cstar'}, 'Before', 1);
    if isfile(sumFile)
        old = readtable(sumFile, 'TextType', 'string');
        try
            rows = [old; rows];
        catch
            warning('sens_summary.csv has different columns - writing a new file next to it.');
            sumFile = strrep(sumFile, '.csv', sprintf('_%s.csv', char(datetime('now','Format','yyyyMMdd_HHmm'))));
        end
    end
    writetable(rows, sumFile);
end

%% ===================== small helpers =====================
function print_lines(title, lines)
    fprintf('%s:\n', title);
    fprintf('    %s\n', lines{:});
end

function delete_if(f)
    if isfile(f), delete(f); end
end

function s = tf(b)
    if b, s = 'true'; else, s = 'false'; end
end
