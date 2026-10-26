function varargout = registry(cmd, varargin)
% REGISTRY  Version / run / scenario registry for OPT_ONE_SENS.
%
%   Structure:  <root>\V1\V1-R01_<name>\{meta, tables, scenarios, logs}
%               <root>\V1\V1_index.xlsx   (sheets Scenarios, Runs, Versions)
%               <root>\V1\V1_index.mat    (same tables, read by find_* functions)
%               <root>\V1\version_info.json (code/data fingerprint of the version)
%   Scenario ID: V<version>-R<run>-S<scenario>, e.g. V1-R03-S012
%
%   One-time migration of existing runs:
%     registry('scan')                    % or registry('scan', {folder1, folder2})
%         -> <root>\registry_proposal.xlsx : review Include / Order / ProposedName /
%            Description, save and close Excel
%     registry('migrate', 1)              % moves the selected runs into V1 and builds the index
%     registry('migrate', 1, 'copy')      % same, but copies instead of moving
%
%   Maintenance:
%     registry('rebuild', V)              % rebuild V<V>_index.xlsx/.mat from the run folders
%     registry('rename', V)               % add/update the scenario count (_88sc) in the run folder names
%
%   Used by OPT_ONE_SENS:
%     outDir  = registry('new_run', cfg)
%     runInfo = registry('load_run', outDir)
%     scName  = registry('scenario_name', runInfo, sid, budget, area, beta, betaSweep)

    switch lower(cmd)
        case 'scan',          reg_scan(varargin{:});
        case 'migrate',       reg_migrate(varargin{:});
        case 'rebuild',       reg_rebuild(varargin{:});
        case 'rename',        reg_rename(varargin{:});
        case 'new_run',       [varargout{1}, varargout{2}] = reg_new_run(varargin{:});
        case 'load_run',      varargout{1} = reg_load_run(varargin{:});
        case 'scenario_name', varargout{1} = reg_scenario_name(varargin{:});
        otherwise,            error('registry: unknown command "%s".', cmd);
    end
end

% =========================================================================
%  SCAN (step 1 of the migration)
% =========================================================================
function reg_scan(roots)
    if nargin < 1 || isempty(roots), roots = {registry_root()}; end
    if ischar(roots) || isstring(roots), roots = cellstr(roots); end

    runDirs = {};
    for r = 1:numel(roots)
        f = dir(fullfile(roots{r}, '**', 'KPI_summary.*'));
        for k = 1:numel(f)
            [~, last] = fileparts(f(k).folder);
            if ~strcmpi(last, 'tables'), continue; end
            runDir = fileparts(f(k).folder);
            if ~isempty(regexp(runDir, '[\\/]V\d+[\\/]V\d+-R\d+_', 'once')), continue; end  % already registered
            runDirs{end+1} = runDir; %#ok<AGROW>
        end
    end
    runDirs = unique(runDirs);
    if isempty(runDirs), fprintf('No unregistered run folders found.\n'); return; end

    rows = [];
    for k = 1:numel(runDirs)
        fprintf('Inspecting (%d/%d): %s\n', k, numel(runDirs), runDirs{k});
        rows = [rows; inspect_run(runDirs{k})]; %#ok<AGROW>
    end
    T = struct2table(rows, 'AsArray', true);
    [~, o] = sort(T.DateNum);
    T = T(o, :);
    T.Order   = (1:height(T))';
    T.DateNum = [];

    out = fullfile(registry_root(), 'registry_proposal.xlsx');
    if isfile(out), delete(out); end
    writetable(T, out, 'Sheet', 'Proposal');
    fprintf('\n%d runs found, %d proposed for inclusion.\n', height(T), sum(T.Include));
    fprintf('Review the proposal (Include = 1/0, Order, ProposedName, Description), save and close:\n  %s\n', out);
    fprintf('Then run: registry(''migrate'', 1)\n');
end

function r = inspect_run(runDir)
    notes = strings(0);
    [K, ~] = read_kpi(runDir);

    % scenario folders
    scenDir = fullfile(runDir, 'scenarios');
    d = dir(scenDir);
    d = d([d.isdir] & ~startsWith({d.name}, '.'));
    nF = numel(d);  nRes = 0;  nErr = 0;  firstRes = '';
    for k = 1:nF
        p = fullfile(scenDir, d(k).name);
        if isfile(fullfile(p, 'results_heavy.mat'))
            nRes = nRes + 1;
            if isempty(firstRes), firstRes = fullfile(p, 'results_heavy.mat'); end
        elseif isfile(fullfile(p, 'error.txt'))
            nErr = nErr + 1;
        end
    end
    nInc = nF - nRes - nErr;

    % grid from the KPI table
    nK = height(K);  nOpt = 0;
    budgets = [];  areas = [];  betas = 0;  nuc = false;  solarRamp = NaN;
    if nK > 0
        vn = K.Properties.VariableNames;
        if ismember('ResultStatus', vn), nOpt = sum(string(K.ResultStatus) == "OPTIMAL"); end
        budgets = unique(K.MaxCost)';
        areas   = unique(K.MaxAreaSolar)';
        if ismember('BetaX', vn),      betas     = unique(K.BetaX)';      end
        if ismember('NucRampX', vn),   nuc       = any(K.NucRampX > 0);   end
        if ismember('SolarRampX', vn), solarRamp = K.SolarRampX(1);       end
    end

    % model settings from RES.P of one scenario
    P = struct();
    if ~isempty(firstRes)
        try
            L = load(firstRes, 'RES');  P = L.RES.P;
        catch ME
            notes(end+1) = "could not read results_heavy: " + string(ME.message);
        end
    else
        notes(end+1) = "no results_heavy.mat";
    end
    if isfield(P, 'OBJECTIVE')
        obj = string(P.OBJECTIVE);
    else
        if any(budgets >= 1e12), obj = "cost"; else, obj = "emissions"; end
        notes(end+1) = "objective inferred from MaxCost";
    end
    if isfield(P, 'EmissionsFactor')
        cp = P.EmissionsFactor;
    else
        cp = 200;  notes(end+1) = "carbon price assumed 200";
    end
    if isfield(P, 'p'), pSol = P.p(2); else, pSol = 100; end
    if isfield(P, 'rampYear') && ~isempty(P.rampYear)
        ramp = "sched" + string(num2str(max(P.rampYear(2,:)) / 1e3));
    elseif ~isnan(solarRamp)
        ramp = "const" + string(num2str(solarRamp * pSol / 1e3));
    else
        ramp = "unknown";  notes(end+1) = "build-rate limits unknown";
    end
    oldCode = ~isempty(fieldnames(P)) && ~isfield(P, 'H_batt');
    if oldCode, notes(end+1) = "no H_batt in RES.P: code before the battery fix?"; end

    % date of the run
    dt = NaT;
    [~, folderName] = fileparts(runDir);
    tok = regexp(folderName, '(\d{8}_\d{6})', 'tokens', 'once');
    if ~isempty(tok), dt = datetime(tok{1}, 'InputFormat', 'yyyyMMdd_HHmmss'); end
    if isnat(dt)
        try
            S0 = jsondecode(read_text(fullfile(runDir, 'meta', 'batch_state.json')));
            dt = datetime(S0.created_at, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
        catch
        end
    end
    if isnat(dt)
        dd = dir(runDir);  dt = datetime(dd(1).datenum, 'ConvertFrom', 'datenum');
    end
    dt.Format = 'yyyy-MM-dd HH:mm';

    % default selection
    if nF < 4,   notes(end+1) = "few scenarios (test run?)"; end
    if nInc > 0, notes(end+1) = sprintf("%d incomplete scenarios", nInc); end
    if nK == 0,  notes(end+1) = "no KPI rows"; end
    inc = nK > 0 && nF >= 4 && nInc == 0 && ~oldCode;

    % proposed name and description
    if obj == "cost", o = "COST"; else, o = "EMIS"; end
    if nuc, n = "nuc"; nTxt = "with nuclear"; else, n = "noNuc"; nTxt = "no nuclear"; end
    nm = o + "_" + n + "_" + ramp;
    if any(betas > 0), nm = nm + "_beta"; end
    desc = sprintf('%s-min, %s, %s, budgets %s bn, land %s km2, %d scenarios', obj, nTxt, ramp, ...
        list_str(budgets / 1e9), list_str(areas), nF);
    if isempty(notes), noteStr = ""; else, noteStr = strjoin(notes, '; '); end

    r = struct();
    r.Include      = double(inc);
    r.Order        = 0;
    r.Date         = string(dt);
    r.DateNum      = datenum(dt); %#ok<DATNM>
    r.ProposedName = nm;
    r.Description  = string(desc);
    r.Objective    = obj;
    r.Nuclear      = double(nuc);
    r.Ramp         = ramp;
    r.CarbonPrice  = cp;
    r.BetaSweep    = double(any(betas > 0));
    r.Budgets_bn   = list_str(budgets / 1e9);
    r.Areas_km2    = list_str(areas);
    r.Betas        = list_str(betas);
    r.N_folders    = nF;
    r.N_results    = nRes;
    r.N_errors     = nErr;
    r.N_KPI        = nK;
    r.N_optimal    = nOpt;
    r.Notes        = noteStr;
    r.RunFolder    = string(runDir);
end

% =========================================================================
%  MIGRATE (step 2 of the migration)
% =========================================================================
function reg_migrate(V, mode)
    if nargin < 1 || isempty(V),    V = 1;         end
    if nargin < 2 || isempty(mode), mode = 'move'; end
    reg  = registry_root();
    prop = fullfile(reg, 'registry_proposal.xlsx');
    if ~isfile(prop), error('No proposal found. Run registry(''scan'') first.'); end

    T = readtable(prop, 'Sheet', 'Proposal', 'TextType', 'string');
    T = T(T.Include == 1, :);
    if isempty(T), fprintf('Nothing selected (Include = 1).\n'); return; end
    T = sortrows(T, 'Order');

    vdir = fullfile(reg, sprintf('V%d', V));
    if ~isfolder(vdir), mkdir(vdir); end
    nxt = next_run_number(vdir, V);

    fprintf('\nPlanned (%s):\n', mode);
    for k = 1:height(T)
        fprintf('  V%d-R%02d_%s  <-  %s\n', V, nxt + k - 1, safe_name(T.ProposedName(k)), T.RunFolder(k));
    end
    resp = input(sprintf('\n%s %d runs into %s ? [y/N]: ', mode, height(T), vdir), 's');
    if ~strcmpi(strtrim(resp), 'y'), fprintf('Aborted.\n'); return; end

    for k = 1:height(T)
        src = char(T.RunFolder(k));
        if ~isfolder(src), warning('Folder not found (skipped): %s', src); continue; end
        nm  = safe_name(T.ProposedName(k));
        dst = fullfile(vdir, sprintf('V%d-R%02d_%s', V, nxt, nm));
        if isfolder(dst), error('Destination already exists: %s', dst); end
        if strcmpi(mode, 'copy'), [ok, msg] = copyfile(src, dst); else, [ok, msg] = movefile(src, dst); end
        if ~ok, warning('Could not %s %s: %s', mode, src, msg); continue; end

        meta = fullfile(dst, 'meta');
        if ~isfolder(meta), mkdir(meta); end
        cfg = struct();
        cfg.version       = V;
        cfg.run           = nxt;
        cfg.run_id        = sprintf('V%d-R%02d', V, nxt);
        cfg.name          = nm;
        cfg.description   = to_char(T.Description(k));
        cfg.created       = to_char(T.Date(k));
        cfg.objective     = to_char(T.Objective(k));
        cfg.nuclear       = logical(T.Nuclear(k));
        cfg.ramp          = to_char(T.Ramp(k));
        cfg.carbon_price  = T.CarbonPrice(k);
        cfg.beta_sweep    = logical(T.BetaSweep(k));
        cfg.budgets       = num_list(T.Budgets_bn(k)) * 1e9;
        cfg.areas         = num_list(T.Areas_km2(k));
        cfg.betas         = num_list(T.Betas(k));
        cfg.test_cells    = [];
        cfg.source        = 'migrated';
        cfg.original_path = src;
        cfg.code_md5      = '';
        cfg.data_md5      = '';
        write_json(fullfile(meta, 'run_config.json'), cfg);
        fprintf('  %s\n', dst);
        nxt = nxt + 1;
    end

    vfile = fullfile(vdir, 'version_info.json');
    if ~isfile(vfile)
        write_json(vfile, new_version_info(V, '', '', ...
            sprintf('V%d: runs migrated from before the registry; fingerprint set by the first new run', V)));
    end
    reg_rebuild(V, reg);
end

% =========================================================================
%  REBUILD THE INDEX OF ONE VERSION
% =========================================================================
function reg_rebuild(V, reg)
    if nargin < 2 || isempty(reg), reg = registry_root(); end
    vdir = fullfile(reg, sprintf('V%d', V));
    d = dir(fullfile(vdir, sprintf('V%d-R*', V)));
    d = d([d.isdir]);

    runs = [];  scen = [];
    for k = 1:numel(d)
        rdir = fullfile(vdir, d(k).name);
        cfg  = reg_load_run(rdir);
        if isempty(cfg), warning('No meta\\run_config.json in %s (skipped).', rdir); continue; end
        [K, Sc] = read_kpi(rdir);
        s = dir(fullfile(rdir, 'scenarios'));
        s = s([s.isdir] & ~startsWith({s.name}, '.'));
        nOpt = 0;
        for j = 1:numel(s)
            r = scen_row(V, cfg, d(k).name, string(s(j).name), rdir, K, Sc);
            nOpt = nOpt + double(r.Status == "OPTIMAL");
            scen = [scen; r]; %#ok<AGROW>
        end
        runs = [runs; run_row(cfg, d(k).name, numel(s), nOpt)]; %#ok<AGROW>
    end
    if isempty(runs), warning('No registered runs in %s.', vdir); return; end

    Runs = sortrows(struct2table(runs, 'AsArray', true), 'Run');
    if isempty(scen)
        Scen = table();
    else
        Scen = sortrows(struct2table(scen, 'AsArray', true), {'Run', 'Scen'});
    end
    Vers = versions_table(reg);

    save(fullfile(vdir, sprintf('V%d_index.mat', V)), 'Runs', 'Scen', 'Vers');
    final = fullfile(vdir, sprintf('V%d_index.xlsx', V));
    tmp   = fullfile(vdir, sprintf('V%d_index_NEW.xlsx', V));
    if isfile(tmp), delete(tmp); end
    if ~isempty(Scen), writetable(Scen, tmp, 'Sheet', 'Scenarios'); end
    writetable(Runs, tmp, 'Sheet', 'Runs');
    writetable(Vers, tmp, 'Sheet', 'Versions');
    [ok, msg] = movefile(tmp, final, 'f');
    if ok
        fprintf('Index V%d: %d runs, %d scenarios -> %s\n', V, height(Runs), height(Scen), final);
    else
        warning('Could not replace %s (open in Excel?). New index saved as %s. (%s)', final, tmp, msg);
    end
end

function r = scen_row(V, cfg, runFolder, nm, rdir, K, Sc)
    tok = regexp(char(nm), '(?:^|_)S(\d+)_', 'tokens', 'once');
    if isempty(tok), sn = NaN; else, sn = str2double(tok{1}); end
    pth = fullfile(rdir, 'scenarios', char(nm));

    budget = NaN;  area = NaN;  beta = NaN;
    if ~isempty(Sc) && isfield(Sc, 'name')
        j = find(strcmp({Sc.name}, char(nm)), 1);
        if ~isempty(j)
            budget = Sc(j).maxCost;  area = Sc(j).maxAreaSolar;
            if isfield(Sc, 'betaBattReserve') && ~isempty(Sc(j).betaBattReserve)
                beta = Sc(j).betaBattReserve;
            end
        end
    end
    i = [];
    if ~isempty(K) && ismember('Scenario', K.Properties.VariableNames)
        i = find(K.Scenario == nm, 1);
    end
    if ~isempty(i)
        status = string(K.ResultStatus(i));
        budget = K.MaxCost(i);  area = K.MaxAreaSolar(i);
        if ismember('BetaX', K.Properties.VariableNames), beta = K.BetaX(i); end
    elseif isfile(fullfile(pth, 'error.txt'))
        status = "ERROR";
    elseif isfile(fullfile(pth, 'results_heavy.mat'))
        status = "NO_KPI";
    else
        status = "INCOMPLETE";
    end
    if isnan(beta), beta = 0; end

    r = struct();
    r.ScenarioID   = string(sprintf('V%d-R%02d-S%03d', V, cfg.run, sn));
    r.Version      = V;
    r.Run          = cfg.run;
    r.Scen         = sn;
    r.Objective    = string(getf(cfg, 'objective', ''));
    r.Nuclear      = double(logical(getf(cfg, 'nuclear', false)));
    r.Ramp         = string(getf(cfg, 'ramp', ''));
    r.CarbonPrice  = getf(cfg, 'carbon_price', NaN);
    r.Beta         = beta;
    r.RETarget2050 = getf(cfg, 're_target_2050', 0);
    r.Budget       = budget;
    r.Area         = area;
    r.Status       = status;
    r.Cost_bn      = kpi_val(K, i, 'TotalCost_AllYears', 1e-9);
    r.Emissions_Mt = kpi_val(K, i, 'TotalEmissions_AllYears', 1e-6);
    r.RE2050       = kpi_val(K, i, 'RenewablesPct2050', 1);
    r.Gas2050_GW   = kpi_val(K, i, 'Cap2050_Gas', 1e-3);
    r.Batt2050_GW  = kpi_val(K, i, 'Cap2050_Battery', 1e-3);
    r.Solar2050_GW = kpi_val(K, i, 'Cap2050_Solar', 1e-3);
    r.Nuc2050_GW   = kpi_val(K, i, 'Cap2050_Nuclear', 1e-3);
    r.Land_km2     = kpi_val(K, i, 'SolarLand_km2', 1);
    r.ScenarioName = nm;
    r.RelPath      = string(fullfile(runFolder, 'scenarios', char(nm)));
end

function r = run_row(cfg, folder, nS, nOpt)
    r = struct();
    r.Run          = cfg.run;
    r.RunID        = string(cfg.run_id);
    r.RunFolder    = string(folder);
    r.Name         = string(getf(cfg, 'name', ''));
    r.Description  = string(getf(cfg, 'description', ''));
    r.Created      = string(getf(cfg, 'created', ''));
    r.Objective    = string(getf(cfg, 'objective', ''));
    r.Nuclear      = double(logical(getf(cfg, 'nuclear', false)));
    r.Ramp         = string(getf(cfg, 'ramp', ''));
    r.CarbonPrice  = getf(cfg, 'carbon_price', NaN);
    r.BetaSweep    = double(logical(getf(cfg, 'beta_sweep', false)));
    r.RETarget2050 = getf(cfg, 're_target_2050', 0);
    r.Budgets_bn   = list_str(getf(cfg, 'budgets', []) / 1e9);
    r.Areas_km2    = list_str(getf(cfg, 'areas', []));
    r.Betas        = list_str(getf(cfg, 'betas', 0));
    r.N_scenarios  = nS;
    r.N_optimal    = nOpt;
    r.Source       = string(getf(cfg, 'source', ''));
    r.CodeMD5      = string(getf(cfg, 'code_md5', ''));
    r.DataMD5      = string(getf(cfg, 'data_md5', ''));
    r.OriginalPath = string(getf(cfg, 'original_path', ''));
end

function T = versions_table(reg)
    d = dir(fullfile(reg, 'V*'));
    d = d([d.isdir]);
    rows = [];
    for k = 1:numel(d)
        if isempty(regexp(d(k).name, '^V\d+$', 'once')), continue; end
        f = fullfile(reg, d(k).name, 'version_info.json');
        if ~isfile(f), continue; end
        vi = jsondecode(read_text(f));
        r = struct();
        r.Version   = getf(vi, 'version', NaN);
        r.Created   = string(getf(vi, 'created', ''));
        r.CodeMD5   = string(getf(vi, 'code_md5', ''));
        r.DataMD5   = string(getf(vi, 'data_md5', ''));
        r.Notes     = string(getf(vi, 'notes', ''));
        r.N_updates = numel(getf(vi, 'history', []));
        rows = [rows; r]; %#ok<AGROW>
    end
    if isempty(rows)
        T = table("none", 'VariableNames', {'Version'});
    else
        T = sortrows(struct2table(rows, 'AsArray', true), 'Version');
    end
end

% =========================================================================
%  NEW RUN (called by OPT_ONE_SENS)
% =========================================================================
function [outDir, info] = reg_new_run(c)
    MARKER = '%% ---------- ONE TIME INPUTS';   % code above this line = run settings (not fingerprinted)
    V      = c.CODE_VERSION;
    reg    = getf(c, 'REG_ROOT', registry_root());
    vdir   = fullfile(reg, sprintf('V%d', V));
    if ~isfolder(vdir), mkdir(vdir); end

    codeMD5 = md5_text_after(c.codeFile, MARKER);
    dataMD5 = md5_file(c.dataFile);
    check_version(reg, vdir, V, codeMD5, dataMD5);

    if strcmpi(c.OBJECTIVE, 'cost'), o = 'COST'; else, o = 'EMIS'; end
    if c.ENABLE_NUCLEAR, n = 'nuc'; else, n = 'noNuc'; end
    ramp = ramp_tag_settings(c.RAMP_SCHEDULE, c.solarRampList);
    nm = sprintf('%s_%s_%s', o, n, ramp);
    if c.ENABLE_BETA_SWEEP, nm = [nm '_beta']; end
    reT = getf(c, 'RE_TARGET_2050', 0);
    if reT > 0, nm = sprintf('%s_RE%02d', nm, round(100 * reT)); end
    if ~isempty(getf(c, 'TEST_CELLS', [])), nm = [nm '_TEST']; end
    tag = char(getf(c, 'RUN_TAG', ''));
    if ~isempty(tag), nm = [nm '_' safe_name(tag)]; end
    nm = sprintf('%s_%dsc', nm, planned_scenarios(c));

    run    = next_run_number(vdir, V);
    outDir = fullfile(vdir, sprintf('V%d-R%02d_%s', V, run, nm));
    mkdir(outDir);
    mkdir(fullfile(outDir, 'meta'));

    info = struct();
    info.version         = V;
    info.run             = run;
    info.run_id          = sprintf('V%d-R%02d', V, run);
    info.name            = nm;
    info.description     = char(getf(c, 'RUN_DESCRIPTION', ''));
    info.created         = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'));
    info.objective       = char(c.OBJECTIVE);
    info.nuclear         = logical(c.ENABLE_NUCLEAR);
    info.ramp            = ramp;
    info.carbon_price    = c.CARBON_PRICE;
    info.beta_sweep      = logical(c.ENABLE_BETA_SWEEP);
    info.budgets         = c.budgetList;
    info.areas           = c.areaList;
    info.betas           = c.betaList;
    info.solar_ramp_list = c.solarRampList;
    info.batt_ramp_list  = c.battRampList;
    info.ramp_schedule   = c.RAMP_SCHEDULE;
    info.re_target_2050  = getf(c, 'RE_TARGET_2050', 0);      % minimum renewable share in 2050 (0 = none)
    info.test_cells      = getf(c, 'TEST_CELLS', []);
    info.source          = 'new';
    info.original_path   = '';
    info.code_md5        = codeMD5;
    info.data_md5        = dataMD5;
    info.code_file       = c.codeFile;
    info.data_file       = c.dataFile;
    write_json(fullfile(outDir, 'meta', 'run_config.json'), info);

    [~, base] = fileparts(c.codeFile);
    copyfile(c.codeFile, fullfile(outDir, 'meta', [base '_snapshot.m.txt']));
    fprintf('\nNew run %s\n  %s\n', info.run_id, outDir);
end

function check_version(reg, vdir, V, codeMD5, dataMD5)
    vfile = fullfile(vdir, 'version_info.json');
    if ~isfile(vfile)
        write_json(vfile, new_version_info(V, codeMD5, dataMD5, ''));
        fprintf('Created version V%d.\n', V);
        return
    end
    vi = jsondecode(read_text(vfile));
    if isempty(getf(vi, 'code_md5', ''))
        vi.code_md5 = codeMD5;  vi.data_md5 = dataMD5;
        vi.history  = add_hist(vi, 'fingerprint set by the first new run');
        write_json(vfile, vi);
        return
    end
    chg = {};
    if ~strcmp(vi.code_md5, codeMD5), chg{end+1} = 'model code'; end
    if ~strcmp(vi.data_md5, dataMD5), chg{end+1} = 'input data file'; end
    if isempty(chg), return; end

    fprintf(2, '\nWARNING: the %s changed since version V%d was fingerprinted.\n', strjoin(chg, ' and '), V);
    resp = input(sprintf('Results expected to be identical (no model change)? [y = keep V%d / n = abort]: ', V), 's');
    if ~strcmpi(strtrim(resp), 'y')
        error('Aborted. If the change affects the results, set CODE_VERSION = %d.', max_version(reg) + 1);
    end
    vi.history  = add_hist(vi, sprintf('fingerprint updated (%s), confirmed by user', strjoin(chg, ', ')));
    vi.code_md5 = codeMD5;  vi.data_md5 = dataMD5;
    write_json(vfile, vi);
end

function n = planned_scenarios(c)
% Number of scenarios OPT_ONE_SENS will build (same loops and TEST_CELLS filter).
    nRamp = numel(c.solarRampList) * numel(c.battRampList);
    TC = getf(c, 'TEST_CELLS', []);
    if isempty(TC)
        n = nRamp * numel(c.budgetList) * numel(c.areaList) * numel(c.betaList);
        return
    end
    nCell = 0;
    for B = c.budgetList(:)'
        for A = c.areaList(:)'
            if any(abs(B/1e9 - TC(:,1)) < 1e-6 & A == TC(:,2)), nCell = nCell + 1; end
        end
    end
    n = nRamp * nCell * numel(c.betaList);
end

function reg_rename(V, reg)
% Add / update the scenario count (_<n>sc) in the run folder names of version V.
    if nargin < 2 || isempty(reg), reg = registry_root(); end
    vdir = fullfile(reg, sprintf('V%d', V));
    d = dir(fullfile(vdir, sprintf('V%d-R*', V)));
    d = d([d.isdir]);
    plan = cell(0, 3);
    for k = 1:numel(d)
        rdir = fullfile(vdir, d(k).name);
        cfg  = reg_load_run(rdir);
        if isempty(cfg), warning('No meta\\run_config.json in %s (skipped).', rdir); continue; end
        s = dir(fullfile(rdir, 'scenarios'));
        nS = sum([s.isdir] & ~startsWith({s.name}, '.'));
        base    = regexprep(char(cfg.name), '_\d+sc$', '');
        newName = sprintf('%s_%dsc', base, nS);
        newDir  = sprintf('V%d-R%02d_%s', V, cfg.run, newName);
        if ~strcmp(newDir, d(k).name)
            plan(end+1, :) = {d(k).name, newDir, newName}; %#ok<AGROW>
        end
    end
    if isempty(plan), fprintf('All run folder names are up to date.\n'); return; end

    fprintf('\nPlanned renames in %s:\n', vdir);
    for k = 1:size(plan, 1), fprintf('  %s  ->  %s\n', plan{k,1}, plan{k,2}); end
    resp = input(sprintf('\nRename %d run folders? [y/N]: ', size(plan, 1)), 's');
    if ~strcmpi(strtrim(resp), 'y'), fprintf('Aborted.\n'); return; end

    for k = 1:size(plan, 1)
        src = fullfile(vdir, plan{k,1});  dst = fullfile(vdir, plan{k,2});
        [ok, msg] = movefile(src, dst);
        if ~ok, warning('Could not rename %s: %s', plan{k,1}, msg); continue; end
        f = fullfile(dst, 'meta', 'run_config.json');
        cfg = jsondecode(read_text(f));
        cfg.name = plan{k,3};
        write_json(f, cfg);
        fprintf('  %s\n', plan{k,2});
    end
    reg_rebuild(V, reg);
end

function info = reg_load_run(outDir)
    f = fullfile(outDir, 'meta', 'run_config.json');
    if isfile(f), info = jsondecode(read_text(f)); else, info = []; end
end

function nm = reg_scenario_name(info, sid, B, A, beta, betaSweep)
    nm = sprintf('V%d_R%02d_S%03d_B%.0f_A%d', info.version, info.run, sid, B / 1e9, A);
    if betaSweep, nm = sprintf('%s_Beta%.1f', nm, beta); end
end

% =========================================================================
%  SMALL HELPERS
% =========================================================================
function [K, Sc] = read_kpi(runDir)
    K = table();  Sc = [];
    fm = fullfile(runDir, 'tables', 'KPI_summary.mat');
    fc = fullfile(runDir, 'tables', 'KPI_summary.csv');
    if isfile(fm)
        try
            w = whos('-file', fm);  names = {w.name};
            if ismember('KPI', names), L = load(fm, 'KPI'); K = L.KPI; end
            if ismember('Sc',  names), L = load(fm, 'Sc');  Sc = L.Sc; end
        catch
        end
    end
    if isempty(K) && isfile(fc), K = readtable(fc); end
    if ~isempty(K) && ismember('Scenario', K.Properties.VariableNames)
        K.Scenario = string(K.Scenario);
    end
end

function v = kpi_val(K, i, f, sc)
    v = NaN;
    if ~isempty(i) && ismember(f, K.Properties.VariableNames), v = double(K.(f)(i)) * sc; end
end

function n = next_run_number(vdir, V)
    d = dir(fullfile(vdir, sprintf('V%d-R*', V)));
    d = d([d.isdir]);
    n = 0;
    for k = 1:numel(d)
        tok = regexp(d(k).name, sprintf('^V%d-R(\\d+)_', V), 'tokens', 'once');
        if ~isempty(tok), n = max(n, str2double(tok{1})); end
    end
    n = n + 1;
end

function m = max_version(reg)
    d = dir(fullfile(reg, 'V*'));
    m = 0;
    for k = 1:numel(d)
        tok = regexp(d(k).name, '^V(\d+)$', 'tokens', 'once');
        if d(k).isdir && ~isempty(tok), m = max(m, str2double(tok{1})); end
    end
end

function vi = new_version_info(V, codeMD5, dataMD5, notes)
    vi = struct();
    vi.version  = V;
    vi.created  = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'));
    vi.code_md5 = codeMD5;
    vi.data_md5 = dataMD5;
    vi.notes    = notes;
    vi.history  = [];
end

function h = add_hist(vi, note)
    e = struct('date', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')), 'note', note);
    h = getf(vi, 'history', []);
    if isempty(h)
        h = e;
    elseif iscell(h)
        h = [h(:); {e}];
    else
        h = [h(:); e];
    end
end

function t = ramp_tag_settings(RS, solarRampList)
    if isempty(RS)
        t = sprintf('const%g', solarRampList(1) * 100 / 1e3);   % 100 MW per build step
    else
        t = sprintf('sched%g', max(RS.solar(:, 2)));
    end
end

function h = md5_text_after(file, marker)
    txt = read_text(file);
    txt = strrep(txt, char([13 10]), char(10));
    k = strfind(txt, marker);
    if ~isempty(k), txt = txt(k(1):end); end
    h = md5_bytes(unicode2native(txt, 'UTF-8'));
end

function h = md5_file(f)
    if ~isfile(f), warning('Data file not found for the fingerprint: %s', f); h = ''; return; end
    fid = fopen(f, 'r');  b = fread(fid, inf, '*uint8');  fclose(fid);
    h = md5_bytes(b);
end

function h = md5_bytes(b)
    md = java.security.MessageDigest.getInstance('MD5');
    if ~isempty(b), md.update(typecast(b(:), 'int8')); end
    d = typecast(int8(md.digest()), 'uint8');
    h = lower(reshape(dec2hex(d, 2).', 1, []));
end

function write_json(f, s)
    fid = fopen(f, 'w', 'n', 'UTF-8');
    if fid < 0, error('Cannot write %s', f); end
    fprintf(fid, '%s', jsonencode(s, 'PrettyPrint', true));
    fclose(fid);
end

function txt = read_text(f)
    fid = fopen(f, 'r', 'n', 'UTF-8');
    if fid < 0, error('Cannot read %s', f); end
    txt = fread(fid, '*char')';
    fclose(fid);
end

function v = getf(s, f, d)
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end

function s = list_str(v)
    if isempty(v), s = ""; else, s = strjoin(compose('%g', v(:)'), ' '); end
end

function v = num_list(x)
    if isnumeric(x), v = x(:)'; v = v(~isnan(v)); return; end
    v = sscanf(char(x), '%f')';
end

function c = to_char(x)
    if isnumeric(x) || (isstring(x) && ismissing(x)), c = ''; else, c = char(string(x)); end
end

function s = safe_name(s)
    s = regexprep(char(s), '[^A-Za-z0-9_\-\.]', '_');
end
