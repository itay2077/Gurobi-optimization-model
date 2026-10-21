%% ============================================================
%  OPT_ONE_SENS.m  - Batch runner for OPT ONE model
%  - Builds a grid of scenarios (ramp, budget, area)
%  - For each scenario:
%       * Runs MILP optimization (min emissions with cost and land limits)
%       * Computes annual KPIs and LCOE
%       * Saves results_heavy.mat
%       * Writes per-scenario kpi_row.csv
%  - At the end:
%       * Builds KPI_summary.csv and KPI_summary.mat
%  - Supports resume via runs\OPT_ONE_SENS\latest\pointer.txt
%  - Skip logic per scenario:
%       * If scDir missing                       -> run
%       * If scDir has results_heavy.mat         -> skip (completed)
%       * If scDir has error.txt only            -> skip (failed, not rerun)
%       * If scDir exists but neither file exists -> run (incomplete)
%% ============================================================

clear; clc;
t_batch = tic;

%% ---------- BASIC CONFIG ----------
%runsRoot   = 'C:\Users\dore\Documents\MATLAB\EnergyOpt_Project\runs';
runsRoot   ='C:\Users\nhmu1\OneDrive\Desktop\עבודה עוזר מחקר\MODEL optimization-Itay';
scriptName = 'OPT_ONE_SENS';

% Scenario lists (edit as needed)
solarRampList = [70];   % upper bound 7 GW/yr; the schedule below is the binding limit
battRampList  = [70];
budgetList    = [420] * 1e9;      % NIS
areaList  = [400 600 850];
ENABLE_NUCLEAR = false; % true = allow 3 GW nuclear (built end of 2042)
ENABLE_BETA_SWEEP  = true;              % true = sweep battery-ELCC credit in the reserve margin (C13)
betaList_onEnabled = [0.1 0.3 0.5 0.7];  % used only if ENABLE_BETA_SWEEP = true

if ENABLE_BETA_SWEEP
    betaList = betaList_onEnabled;
else
    betaList = 0;                        % baseline: battery gets no credit in C13 (today's behaviour)
end
% ---- time-varying build-rate limits [year GW/yr]; set RAMP_SCHEDULE = [] for constant limits ----
RAMP_SCHEDULE.solar = [2025 2;  2030 3;  2035 5;  2040 7;  2050 7];
RAMP_SCHEDULE.batt  = [2025 2;  2030 3;  2035 5;  2040 7;  2050 7];

OBJECTIVE      = 'cost';    % 'emissions' (current model) | 'cost' (economic minimum)
CARBON_PRICE   = 200;       % NIS/tCO2e inside the cost (0 = direct-cost minimum)
if strcmp(OBJECTIVE, 'cost')
    budgetList = 1e13;      % effectively unconstrained (one run per land cap)
end

% Gurobi path (adjust if needed)
addpath('C:\gurobi1302\win64\matlab'); savepath;


%% ---------- OUTDIR SELECTION (pointer, choose, or new) ----------
latestDir = fullfile(runsRoot, scriptName, 'latest');
if ~isfolder(latestDir)
    mkdir(latestDir);
end
ptrFile = fullfile(latestDir, 'pointer.txt');

outDir = '';
% 1) Try read pointer
if isfile(ptrFile)
    try
        cand = strtrim(fileread(ptrFile));
        if isfolder(cand)
            fprintf('Found existing run folder via pointer:\n  %s\n', cand);
            resp = input('Use this folder (U), choose another (C), or create new (N)? [U/C/N]: ', 's');
            if isempty(resp)
                resp = 'U';
            end
            resp = upper(resp(1));
            switch resp
                case 'U'
                    outDir = cand;
                case 'C'
                    sel = uigetdir(runsRoot, 'Select existing run folder');
                    if sel == 0
                        error('No folder selected. Aborting.');
                    end
                    outDir = sel;
                case 'N'
                    % handled below if outDir still empty
                otherwise
                    warning('Unrecognized choice, creating new run folder.');
            end
        end
    catch
        warning('Could not read or use pointer.txt, will create or select folder anew.');
    end
end

% 2) If still empty, ask user: choose existing or create new
if isempty(outDir)
    resp2 = input('Create new run folder (N) or choose existing (C)? [N/C]: ', 's');
    if isempty(resp2)
        resp2 = 'N';
    end
    resp2 = upper(resp2(1));
    switch resp2
        case 'C'
            sel = uigetdir(runsRoot, 'Select existing run folder');
            if sel == 0
                error('No folder selected. Aborting.');
            end
            outDir = sel;
        case 'N'
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');  % user requested date and time as name
            outDir = fullfile(runsRoot, scriptName, timestamp);
        otherwise
            error('Unrecognized choice. Aborting.');
    end
end

% 3) Ensure per-run subfolders exist
d_scen = fullfile(outDir, 'scenarios');
d_tbls = fullfile(outDir, 'tables');
d_logs = fullfile(outDir, 'logs');
d_meta = fullfile(outDir, 'meta');
for dd = {outDir, d_scen, d_tbls, d_logs, d_meta}
    if ~isfolder(dd{1})
        mkdir(dd{1});
    end
end

% 4) Update pointer.txt to the current outDir
fid = fopen(ptrFile, 'w');
if fid > 0
    fprintf(fid, '%s\n', outDir);
    fclose(fid);
end

% 5) State file (meta, optional)
stateFile = fullfile(d_meta, 'batch_state.json');
if ~isfile(stateFile)
    S0 = struct();
    S0.created_at      = datestr(now, 31);
    S0.total           = 0;
    S0.completed_names = {};
    S0.script          = scriptName;
    S0.outDir          = outDir;
    S0.next_index      = 1;
    fid = fopen(stateFile, 'w', 'n', 'UTF-8');
    if fid > 0
        fwrite(fid, jsonencode(S0, 'PrettyPrint', true), 'char');
        fclose(fid);
    end
end

%% ---------- ONE TIME INPUTS: DEMAND, CF, EMISSION FACTORS ----------
%xlsFile   = 'C:\Users\dore\Desktop\Project\ROTH 1 Model.xlsx';
xlsFile   = 'C:\Users\nhmu1\OneDrive\Desktop\עבודה עוזר מחקר\MODEL optimization-Itay\ROTH 1 Model - Itay.xlsx'
sheetName = 'ROTH 1.0';
rangeDem  = 'J6:J245285';        % Demand
startYr   = 2023;
yearLen   = 8760;
sheetCapex= 'capex';
sheetOpex= 'opex';
sheetVarOpex= 'var-opex';

Demand = xlsread(xlsFile, sheetName, rangeDem);
Demand = Demand(:);
T      = numel(Demand);
nYears = floor(T / yearLen);

% Costs
%%
cap = readtable(xlsFile, 'Sheet', sheetCapex);
op  = readtable(xlsFile, 'Sheet', sheetOpex);
var = readtable(xlsFile, 'Sheet', sheetVarOpex);


years = cap.year;
capMatrix = table2array(cap(:, 2:end));
opMatrix = table2array(op(:, 2:end));
varMatrix = table2array(var(:, 2:end));

getCapexValue = @(sourceIdx, targetYear) capMatrix(years == targetYear, sourceIdx);
getOpexValue = @(sourceIdx, targetYear) opMatrix(years == targetYear, sourceIdx);
getVarValue = @(sourceIdx, targetYear) varMatrix(years == targetYear, sourceIdx);




%%


% Solar CF
cf_single = readmatrix(xlsFile, 'Sheet', sheetName, 'Range', 'L6:L8765');
cf_single(isnan(cf_single)) = 0;
cf = repmat(cf_single, ceil(T / 8760), 1);
cf = cf(1:T);

% Solar EF per year
rangeSolarEF = 'C9:C36';   % 2023-2050 (row 3 = 2017)
cSolar_year  = readmatrix(xlsFile, 'Sheet', 'PVEmissions', 'Range', rangeSolarEF);
cSolar_year  = cSolar_year(:);
cSolar_year  = cSolar_year(1:nYears);
cSolar_t     = repelem(cSolar_year, yearLen);
cSolar_t     = cSolar_t(1:T);

% Battery EF per year
rangeBattEF = 'C8:C35';    % 2023-2050 (row 2 = 2017)
cBatt_year  = readmatrix(xlsFile, 'Sheet', 'StoargeEmission', 'Range', rangeBattEF);
cBatt_year  = cBatt_year(:);
cBatt_year  = cBatt_year(1:nYears);
cBatt_t     = repelem(cBatt_year, yearLen);
cBatt_t     = cBatt_t(1:T);

%% ---------- MODEL PARAMETERS (COMMON ACROSS SCENARIOS) ----------
P_common            = struct();

P_common.OBJECTIVE       = OBJECTIVE;
P_common.EmissionsFactor = CARBON_PRICE;      % replaces the fixed 200

% Order: [1 Nuclear; 2 Solar; 3 Gas; 4 Coal; 5 Battery]
P_common.n_sources  = 5;
P_common.init_cap   = [0;5900;11700;5600;369];        % MW
P_common.c          = [0.012;0.03695;0.486;0.9;0.04]; % t CO2 / MWh
P_common.p          = [1000;100;100;100;100];         % MW per build step
P_common.lifeTime   = [60,30,30,30,20];               % years

% --- ECONOMIC DISCOUNTING PARAMETERS ---
P_common.r          = 0.06;                           % Discount Rate (6%)

% Capital Recovery Factor (CRF) - Calculates the PMT factor for CAPEX
% Equivalent to PMT(6%, lifeTime, -1, 0, 0)
P_common.CRF        = (P_common.r .* (1 + P_common.r).^P_common.lifeTime) ./ ...
                      ((1 + P_common.r).^P_common.lifeTime - 1);

P_common.capex_per_MW = [235; 31; 37; 150; 13] .* (P_common.CRF') * 1e5; % Example if used later
P_common.areaPerSolar = 0.0075;                       % km^2 / MW solar


P_common.Capex = capMatrix;
P_common.Opex = opMatrix;
P_common.Var = varMatrix;

% Battery parameters
P_common.E0      = 0;     % initial energy
P_common.eta_ch  = 0.95;
P_common.eta_dis = 0.90;
P_common.H_batt  = 4;     % hours of storage at rated power

% Time and EF
P_common.Demand   = Demand;
P_common.cf       = cf;
P_common.cSolar_t = cSolar_t;
P_common.cBatt_t  = cBatt_t;
P_common.startYr  = startYr;
P_common.yearLen  = yearLen;
P_common.T        = T;
P_common.nYears   = nYears;

% Pre-calculate yearly discount factors (PV factor = 1 / (1+r)^y)
% Assuming year 1 (2023) is discounted by 0 years (factor = 1.0)
P_common.df_yearly = (1 + P_common.r) .^ -(0:(P_common.nYears-1))';
% ---- year-dependent build-rate limits [MW per year] ----
yrsR = startYr:startYr+nYears-1;
P_common.rampYear = [];
if ~isempty(RAMP_SCHEDULE)
    P_common.rampYear = nan(5, nYears);
    S = RAMP_SCHEDULE.solar;  B = RAMP_SCHEDULE.batt;
    P_common.rampYear(2,:) = 1e3 * interp1(S(:,1), S(:,2), min(max(yrsR, S(1,1)), S(end,1)));
    P_common.rampYear(5,:) = 1e3 * interp1(B(:,1), B(:,2), min(max(yrsR, B(1,1)), B(end,1)));
    disp('Build-rate schedule [GW/yr] for 2023, 2025, 2030, 2035, 2040, 2050:');
    disp(round(P_common.rampYear([2 5], [1 3 8 13 18 28]) / 1e3, 1));
end

%% ---------- BUILD SCENARIOS ----------
Sc  = struct('name', {}, 'meta', {}, 'maxCost', {}, 'maxAreaSolar', {}, 'maxRamp', {});
sid = 0;

for s = solarRampList
    for b = battRampList
        for B = budgetList
            for A = areaList
                for beta = betaList
                     sid = sid + 1;
                     scName = sprintf('S%03d_Sol%03d_Bat%03d_B%.1f_A%d', sid, s, b, B/1e11, A);
                     if ENABLE_BETA_SWEEP
                        scName = sprintf('%s_Beta%.1f', scName, beta);
                     end

                     Sc(sid).name         = scName;
                     Sc(sid).maxCost      = B;
                     Sc(sid).maxAreaSolar = A;
                     Sc(sid).betaBattReserve = beta;
                     Sc(sid).meta         = struct('SolarRamp', s, 'BattRamp', b, 'NucRamp', 3*ENABLE_NUCLEAR);
                % Ramp vector based on p
                     Sc(sid).maxRamp      = [3 * ENABLE_NUCLEAR * P_common.p(1); ...
                                         s * P_common.p(2); ...
                                        50 * P_common.p(3); ...
                                        0 * P_common.p(4); ...
                                         b * P_common.p(5)];
                end
            end
        end
    end
end

% ---- optional: run only selected cells [budget(1e9) area(km2)]; [] = full grid ----
TEST_CELLS = [];
if ~isempty(TEST_CELLS)
    keep = false(1, numel(Sc));
    for k = 1:numel(Sc)
        keep(k) = any(abs(Sc(k).maxCost/1e9 - TEST_CELLS(:,1)) < 1e-6 & ...
                      Sc(k).maxAreaSolar == TEST_CELLS(:,2));
    end
    Sc = Sc(keep);
    fprintf('TEST MODE: %d scenarios selected\n', numel(Sc));
end



nAll = numel(Sc);

%% ---------- UPDATE STATE FILE WITH TOTAL SCENARIOS ----------
try
    S_state = jsondecode(fileread(stateFile));
catch
    S_state = struct();
end
S_state.created_at      = datestr(now, 31);
S_state.total           = nAll;
if ~isfield(S_state, 'completed_names') || isempty(S_state.completed_names)
    S_state.completed_names = {};
end
S_state.script          = scriptName;
S_state.outDir          = outDir;
if ~isfield(S_state, 'next_index')
    S_state.next_index = 1;
end
fid = fopen(stateFile, 'w', 'n', 'UTF-8');
if fid > 0
    fwrite(fid, jsonencode(S_state, 'PrettyPrint', true), 'char');
    fclose(fid);
end

%% ---------- RUN LOOP: COMPLETED & SKIP LOGIC ----------
KPI_rows   = table();
runCounter = 0;
nToRun = 0;
for kk = 1:nAll
    scName2 = Sc(kk).name;
    scDir2  = fullfile(d_scen, scName2);

    if ~isfolder(scDir2)
        nToRun = nToRun + 1;
    else
        hasResults2 = isfile(fullfile(scDir2, 'results_heavy.mat'));
        hasError2   = isfile(fullfile(scDir2, 'error.txt'));
        if ~(hasResults2 || hasError2)
            nToRun = nToRun + 1;
        end
    end
end

fprintf('Total scenarios: %d | To run: %d | Skipped: %d\n', nAll, nToRun, nAll - nToRun);


for k = 1:nAll
    scName = Sc(k).name;
    scDir  = fullfile(d_scen, scName);

    % Decide whether to run this scenario
    needToRun  = true;
    reasonSkip = '';

    if ~isfolder(scDir)
        % no folder -> must run
        needToRun = true;
    else
        hasResults = isfile(fullfile(scDir, 'results_heavy.mat'));
        hasError   = isfile(fullfile(scDir, 'error.txt'));
        if hasResults
            needToRun  = false;
            reasonSkip = 'completed (results_heavy.mat exists)';
        elseif hasError
            needToRun  = false;
            reasonSkip = 'previous error (error.txt exists)';
        else
            % folder exists but no results and no error -> rerun
            needToRun = true;
        end
    end

    if ~needToRun
        fprintf('[SKIP] %s - %s\n', scName, reasonSkip);
        continue;
    end

    % We will run this scenario
    runCounter = runCounter + 1;
    bannerTxt  = sprintf('=== [%2d/%2d] %s ===', runCounter, nToRun, scName);
    print_banner(bannerTxt);

    if ~isfolder(scDir)
        mkdir(scDir);
    end

    % Open diary log
    logFile = fullfile(scDir, 'run.log');
    diary(logFile);

    t0 = tic;
    try
        % Pack scenario specific parameters
        maxCost      = Sc(k).maxCost;
        maxAreaSolar = Sc(k).maxAreaSolar;
        maxRamp      = Sc(k).maxRamp;

        fprintf('Scenario: %s\n', scName);
        fprintf('  maxCost      : %.3e NIS\n', maxCost);
        fprintf('  maxAreaSolar : %.1f km^2\n', maxAreaSolar);
        fprintf('  maxRamp      : [%.1f %.1f %.1f %.1f %.1f] MW per period\n', ...
            maxRamp(1), maxRamp(2), maxRamp(3), maxRamp(4), maxRamp(5));

        % Solve single scenario
        RES = solve_opt_one_once(maxCost, maxAreaSolar, maxRamp, Sc(k).betaBattReserve, P_common);
        
        % If solver returned no solution vector - treat as failed run (no results saved)
        hasX = isfield(RES,'result') && isstruct(RES.result) && isfield(RES.result,'x') && ~isempty(RES.result.x);
        
        if ~hasX
            statusStr = "UNKNOWN_STATUS";
            if isfield(RES,'ResultStatus') && ~isempty(RES.ResultStatus)
                statusStr = string(RES.ResultStatus);
            elseif isfield(RES.result,'status') && ~isempty(RES.result.status)
                statusStr = string(RES.result.status);
            end
        
            fprintf(2,'[NO SOLUTION] %s - status=%s (no incumbent x). Marking error and skipping save.\n', scName, statusStr);
        
            errFile = fullfile(scDir, 'error.txt');
            fidErr  = fopen(errFile, 'w', 'n', 'UTF-8');
            if fidErr > 0
                fprintf(fidErr, 'No incumbent solution vector (result.x missing/empty).\n');
                fprintf(fidErr, 'Status: %s\n', statusStr);
                fclose(fidErr);
            end
        
            diary off;
            continue; % go to next scenario
        end
        
        % If we got here - safe to save outputs
        save(fullfile(scDir, 'results_heavy.mat'), 'RES', '-v7.3');


        % Extract KPI scalars from RES
        % Scenario descriptive part
        Scenario      = string(scName);
        NucRampX      = Sc(k).meta.NucRamp;
        SolarRampX    = Sc(k).meta.SolarRamp;
        BattRampX     = Sc(k).meta.BattRamp;
        MaxCost       = maxCost;
        MaxAreaSolar  = maxAreaSolar;
        BetaX = Sc(k).betaBattReserve;

        % Macro costs and emissions (all years)
        TotalCost_AllYears   = RES.TotalCost_AllYears;
        TotalEmissions_AllYears = RES.TotalEmissions_AllYears;
        TotalExternalities_AllYears=RES.TotalExternalities_AllYears;
        TotalOPEX_AllYears   = RES.TotalOPEX_AllYears;
        TotalCAPEX_AllYears  = RES.TotalCAPEX_AllYears;

        % Base and target years (cost and emissions)
        Emissions_BaseYear   = RES.Emissions_BaseYear;
        Emissions_TargetYear = RES.Emissions_TargetYear;
        Externalities_BaseYear= RES.Externalities_BaseYear;
        Externalities_TargetYear = RES.Externalities_TargetYear;
        OPEX_BaseYear        = RES.OPEX_BaseYear;
        OPEX_TargetYear      = RES.OPEX_TargetYear;
        CAPEX_BaseYear       = RES.CAPEX_BaseYear;
        CAPEX_TargetYear     = RES.CAPEX_TargetYear;
        TotalCost_BaseYear   = RES.TotalCost_BaseYear;
        TotalCost_TargetYear = RES.TotalCost_TargetYear;

        % LCOE metrics (NIS per kWh)
        LCOE_AllYears_NIS_per_kWh        = RES.LCOE_AllYears_NIS_per_kWh;
        LCOE_BaseYearPlus1_NIS_per_kWh   = RES.LCOE_BaseYearPlus1_NIS_per_kWh;
        LCOE_TargetYear_NIS_per_kWh      = RES.LCOE_TargetYear_NIS_per_kWh;

        % Renewables share 2050
        RenewablesPct2050    = RES.RenewablesPct2050;

        % Capacities 2050
        Cap2050_Nuclear      = RES.Cap2050(1);
        Cap2050_Solar        = RES.Cap2050(2);
        Cap2050_Gas          = RES.Cap2050(3);
        Cap2050_Coal         = RES.Cap2050(4);
        Cap2050_Battery      = RES.Cap2050(5);

        % Solar land usage
        SolarLand_km2        = RES.SolarLand_km2;

         % Dump KPIs
        TotalDump_AllYears_MWh    = RES.TotalDump_AllYears_MWh;
        Dump2050_MWh              = RES.Dump2050_MWh;

        % Technical run info
        durSec       = toc(t0);
        Runtime_hrs  = durSec / 3600;
        ResultStatus = "";
        MIPGap       = NaN;
        if isfield(RES, 'result') && isstruct(RES.result)
            if isfield(RES.result, 'status')
                ResultStatus = string(RES.result.status);
            end
            if isfield(RES.result, 'mipgap')
                MIPGap = RES.result.mipgap;
            end
        end

        % Print duration
        dur    = seconds(durSec);
        dur.Format = 'hh:mm:ss';
        fprintf('...%s finished in %s (%.1f min, %.2f hr)\n', scName, char(dur), durSec/60, Runtime_hrs);

        % Build KPI row table
        kpiRow = table( ...
        Scenario, ...
        NucRampX, SolarRampX, BattRampX, ...
        MaxCost, MaxAreaSolar, BetaX, ...
        TotalCost_AllYears, TotalEmissions_AllYears, ...
        TotalExternalities_AllYears,TotalOPEX_AllYears, TotalCAPEX_AllYears, ...
        Emissions_BaseYear, Emissions_TargetYear, ...
        Externalities_BaseYear,Externalities_TargetYear,OPEX_BaseYear, OPEX_TargetYear, ...
        CAPEX_BaseYear, CAPEX_TargetYear, ...
        TotalCost_BaseYear, TotalCost_TargetYear, ...
        LCOE_AllYears_NIS_per_kWh, ...
        LCOE_BaseYearPlus1_NIS_per_kWh, ...
        LCOE_TargetYear_NIS_per_kWh, ...
        RenewablesPct2050, ...
        Cap2050_Nuclear, Cap2050_Solar, Cap2050_Gas, Cap2050_Coal, Cap2050_Battery, ...
        SolarLand_km2, ...
        TotalDump_AllYears_MWh, Dump2050_MWh, ...
        Runtime_hrs, ResultStatus, MIPGap, ...
        'VariableNames', { ...
            'Scenario', ...
            'NucRampX','SolarRampX','BattRampX', ...
            'MaxCost','MaxAreaSolar','BetaX', ...
            'TotalCost_AllYears','TotalEmissions_AllYears', ...
            'TotalExternalities_AllYears','TotalOPEX_AllYears','TotalCAPEX_AllYears', ...
            'Emissions_BaseYear','Emissions_TargetYear', ...
            'Externalities_BaseYear','Externalities_TargetYear','OPEX_BaseYear','OPEX_TargetYear', ...
            'CAPEX_BaseYear','CAPEX_TargetYear', ...
            'TotalCost_BaseYear','TotalCost_TargetYear', ...
            'LCOE_AllYears_NIS_per_kWh', ...
            'LCOE_BaseYearPlus1_NIS_per_kWh', ...
            'LCOE_TargetYear_NIS_per_kWh', ...
            'RenewablesPct2050', ...
            'Cap2050_Nuclear','Cap2050_Solar','Cap2050_Gas','Cap2050_Coal','Cap2050_Battery', ...
            'SolarLand_km2', ...
            'TotalDump_AllYears_MWh','Dump2050_MWh', ...
            'Runtime_hrs','ResultStatus','MIPGap' ...
        } ...
    );


        % Append to accumulator
        KPI_rows = [KPI_rows; kpiRow]; %#ok<AGROW>

        % Write per scenario KPI CSV
        writetable(kpiRow, fullfile(scDir, 'kpi_row.csv'));

        % Update state file: mark scenario as completed
        try
            S_state = jsondecode(fileread(stateFile));
        catch
            S_state = struct();
        end
        if ~isfield(S_state, 'completed_names') || isempty(S_state.completed_names)
            S_state.completed_names = {};
        end
        if ~ismember(scName, S_state.completed_names)
            S_state.completed_names{end+1} = scName; %#ok<AGROW>
        end
        S_state.next_index = k + 1;
        S_state.total      = nAll;
        S_state.script     = scriptName;
        S_state.outDir     = outDir;
        fid = fopen(stateFile, 'w', 'n', 'UTF-8');
        if fid > 0
            fwrite(fid, jsonencode(S_state, 'PrettyPrint', true), 'char');
            fclose(fid);
        end

    catch ME
        fprintf(2, 'ERROR in scenario %s: %s\n', scName, ME.message);
        errFile = fullfile(scDir, 'error.txt');
        fidErr  = fopen(errFile, 'w', 'n', 'UTF-8');
        if fidErr > 0
            fprintf(fidErr, '%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
            fclose(fidErr);
        end
        % continue to next scenario
    end

    diary off;
end

%% ---------- SAVE KPI SUMMARY ----------
fKPI = dir(fullfile(d_scen, '*', 'kpi_row.csv'));
KPI_rows = table();
for kk = 1:numel(fKPI)
    KPI_rows = [KPI_rows; readtable(fullfile(fKPI(kk).folder, fKPI(kk).name))]; %#ok<AGROW>
end
if ~isempty(KPI_rows)
    KPI = KPI_rows;
    writetable(KPI, fullfile(d_tbls, 'KPI_summary.csv'));
    save(fullfile(d_tbls, 'KPI_summary.mat'), 'KPI', 'Sc', '-v7.3');
    fprintf('\nKPI summary saved to:\n  %s\n  %s\n', ...
        fullfile(d_tbls, 'KPI_summary.csv'), ...
        fullfile(d_tbls, 'KPI_summary.mat'));
else
    fprintf('\nNo KPI rows generated. Nothing to save.\n');
end

%% ---------- TOTAL BATCH DURATION ----------
totalSec = toc(t_batch);
totalDur = seconds(totalSec);
totalDur.Format = 'hh:mm:ss';
fprintf('\nTOTAL batch time: %s (%.1f min, %.2f hr)\n', char(totalDur), totalSec/60, totalSec/3600);
fprintf('OutDir: %s\n', outDir);

%% ============================================================
%  LOCAL FUNCTIONS
% ============================================================

function print_banner(txt)
    fprintf('\n%s\n%s\n%s\n\n', ...
        repmat('=', 1, numel(txt)), ...
        txt, ...
        repmat('=', 1, numel(txt)));
end
function RES = solve_opt_one_once(maxCost, maxAreaSolar, maxRamp, betaBattReserve, P)
% Single scenario solver based on OPT ONE formulation (with safe TimeLimit handling)
% All code comments in English as requested.

    t_start = tic;

    % ---------- Unpack parameters ----------
    n_sources     = P.n_sources;
    init_cap      = P.init_cap;
    c             = P.c;
    lifeTime      = P.lifeTime;  
    p             = P.p;
    areaPerSolar  = P.areaPerSolar;
    EmissionsFactor = P.EmissionsFactor;
    cap = P.Capex;
    op = P.Opex;
    var = P.Var;
    % --- SCALING FOR GUROBI NUMERICAL STABILITY ---
    %this part was added to help the solver find acuurate sollutions
    % Dividing all monetary inputs by 1 million for the solver equations
    SCALE = 1e6; 
    maxCost_opt = maxCost / SCALE;
    cap_opt     = cap / SCALE;
    op_opt      = op / SCALE;
    var_opt     = var / SCALE;
    EF_opt      = EmissionsFactor / SCALE;




    E0            = P.E0;
    eta_ch        = P.eta_ch;
    eta_dis       = P.eta_dis;
    H_batt        = P.H_batt;

    Demand        = P.Demand;
    cf            = P.cf;
    cSolar_t      = P.cSolar_t;
    cBatt_t       = P.cBatt_t;

    startYr       = P.startYr;
    yearLen       = P.yearLen;
    T             = P.T;
    nYears        = P.nYears;
    % --- Economic Discounting ---
    CRF           = P.CRF;
    df_yearly     = P.df_yearly;

    TargetYear = 2050; % KPI target year

    % ---------- Indexing ----------
    idxU   = @(i,t)                   (i-1)*T           + t;
    idxZ   = @(i,t)   n_sources*T   + (i-1)*T           + t;
    idxK   = @(i,t)   n_sources*T*2 + (i-1)*T           + t;
    idxChB = @(t)     n_sources*T*3 +                    t;
    idxDump= @(t)     n_sources*T*3 + T   +              t;
    idxE   = @(t)     n_sources*T*3 + 2*T +              t;

    n_U    = n_sources * T;
    n_Z    = n_sources * T;
    n_K    = n_sources * T;
    n_ChB  = T;
    n_Dump = T;
    n_E    = T;

    % Add T variables for cumulative cost C(t)
    numVars = n_U + n_Z + n_K + n_ChB + n_Dump + n_E + T;
    idxC    = @(t) n_U + n_Z + n_K + n_ChB + n_Dump + n_E + t;

    lb    = zeros(numVars, 1);
    ub    = inf(numVars, 1);
    vtype = repmat('C', 1, numVars);

    % Lower bounds for C(t)
    for t = 1:T
        lb(idxC(t)) = 0;
    end
    
    % Budget constraint: Apply the upper bound ONLY to the final hour
    ub(idxC(T)) = maxCost_opt;

    

    % ---------- Objective: minimize total emissions ----------
    obj = zeros(numVars, 1);

    % Constant EF for thermal sources [1 3 4]
    for i = [1 3 4]
        obj(idxU(i,1:T)) = c(i);
    end

    % Time-varying EF for solar and battery
    obj(idxU(2,1:T))  = cSolar_t;     % solar to grid
    obj(idxU(5,1:T))  = cBatt_t;      % battery discharge to grid
    obj(idxDump(1:T)) = cSolar_t;     % curtailed solar charged to solar EF
    obj(idxChB(1:T))  = cSolar_t;     % solar sent to battery charged to solar EF

    if strcmp(P.OBJECTIVE, 'cost')
        obj(:)         = 0;
        obj(idxC(T))   = 1;     % minimize total discounted cost (CAPEX + OPEX + carbon cost)
        ub(idxC(T))    = Inf;   % no budget constraint
    end

    % ---------- Constraints triplets ----------
    global I J V
    I = []; J = []; V = [];
    row   = 0;
    rhs   = [];
    sense = '';

    % (C1) Demand balance: sum_i U(i,t) = Demand(t)
    for t = 1:T
        row = row + 1;
        for i = 1:n_sources
            addCoef(row, idxU(i,t), 1);
        end
        rhs(row,1)   = Demand(t);
        sense(row,1) = '=';
    end

    % (C2) Solar split:
    % U_solar_grid(t) + ChB(t) + Dump(t) = cf(t) * K_solar(t)
    for t = 1:T
        row = row + 1;
        addCoef(row, idxU(2,t),   1);
        addCoef(row, idxChB(t),   1);
        addCoef(row, idxDump(t),  1);
        addCoef(row, idxK(2,t),  -cf(t));
        rhs(row,1)   = 0;
        sense(row,1) = '=';
    end

    % (C2b) U(i,t) <= K(i,t) for sources [1 3 4]
    for i = [1 3 4]
        for t = 1:T
            row = row + 1;
            addCoef(row, idxU(i,t), 1);
            addCoef(row, idxK(i,t), -1);
            rhs(row,1)   = 0;
            sense(row,1) = '<';
        end
    end

    % (C3) Capacity dynamics
    for i = 1:n_sources
        % t = 1
        row = row + 1;
        addCoef(row, idxK(i,1), 1);
        addCoef(row, idxZ(i,1), -p(i));
        rhs(row,1)   = init_cap(i);
        sense(row,1) = '=';

        % t >= 2
        for t = 2:T
            row = row + 1;
            addCoef(row, idxK(i,t),   1);
            addCoef(row, idxK(i,t-1), -1);
            addCoef(row, idxZ(i,t),   -p(i));
            rhs(row,1)   = 0;
            sense(row,1) = '=';
        end
    end

    % (C4) Build window for sources 2-5 (yearly, except last year for flexibility)
    for i = 1:n_sources
        for t = 1:T
            if (i ~= 1) && (mod(t,8760) ~= 0 || t > T-8760)
                row = row + 1;
                addCoef(row, idxZ(i,t), 1);
                rhs(row,1)   = 0;
                sense(row,1) = '=';
            end
        end
    end

    % (C5) Nuclear build only every 20 years
    for t = 1:T
        if mod(t, 8760*20) ~= 0
            row = row + 1;
            addCoef(row, idxZ(1,t), 1);
            rhs(row,1)   = 0;
            sense(row,1) = '=';
        end
    end

    % (C6) Solar land use: areaPerSolar * K_solar(t) <= maxAreaSolar
    for t = 1:T
        row = row + 1;
        addCoef(row, idxK(2,t), areaPerSolar);
        rhs(row,1)   = maxAreaSolar;
        sense(row,1) = '<';
    end
    

  % (C7) Sparse Cost Accumulation (Discounted to Present Value)
    for t = 1:T
        idxy = ceil(t / 8760);
        df = df_yearly(idxy);
        
        row = row + 1; % <--- כאן נמחקה הטעות!
        
        % C(t) - C(t-1)
        addCoef(row, idxC(t), 1);
        if t > 1
            addCoef(row, idxC(t-1), -1);
        end
        
        % 1. CAPEX on NEW builds Z 
        if mod(t, 8760) == 0
            pv_multiplier = sum(df_yearly(idxy:nYears));
            for i = 1:n_sources
                annualized_capex = cap_opt(idxy,i) * p(i) * CRF(i); 
                addCoef(row, idxZ(i,t), -annualized_capex * pv_multiplier);
            end
        end
        
        % 2. Fixed OPEX (Discounted)
        if mod(t, 8760) == 0
            for i = 1:n_sources
                 addCoef(row, idxK(i,t-1), -op_opt(idxy,i) * df);
             end
        end
        
        % 3. Var-OPEX (Discounted)
        addCoef(row, idxK(2,t), -var_opt(idxy,2) * cf(t) * df);
        for i = 1:n_sources
            if i ~= 2
                addCoef(row, idxU(i,t), -var_opt(idxy,i) * df);
            end
        end
        
        % 4. Externalities (carbon cost on ALL life-cycle emissions)
        for i = [1 3 4]
             addCoef(row, idxU(i,t), -c(i) * EF_opt * df);
        end
        addCoef(row, idxK(2,t), -cSolar_t(t) * cf(t) * EF_opt * df);   % solar: all generation (cf*K)
        addCoef(row, idxU(5,t), -cBatt_t(t)  * EF_opt * df);           % battery discharge
        
        rhs(row,1)   = 0;
        sense(row,1) = '=';
    end

    % (C8) Ramp limit: K(i,t) - K(i,t-1) <= maxRamp(i)
    for i = 1:n_sources
        for t = 2:T
            row = row + 1;
            addCoef(row, idxK(i,t),   1);
            addCoef(row, idxK(i,t-1), -1);
            rhs(row,1)   = maxRamp(i);
            sense(row,1) = '<';
        end
    end
    


    % (C9) Battery energy balance
    for t = 1:T
        row = row + 1;
        if t == 1
            addCoef(row, idxE(1),   1);
            addCoef(row, idxChB(1), -eta_ch);
            addCoef(row, idxU(5,1),  1/eta_dis);
            rhs(row,1)   = E0;
        else
            addCoef(row, idxE(t),     1);
            addCoef(row, idxE(t-1),  -1);
            addCoef(row, idxChB(t),  -eta_ch);
            addCoef(row, idxU(5,t),   1/eta_dis);
            rhs(row,1)   = 0;
        end
        sense(row,1) = '=';
    end

    % (C10) Battery energy capacity: E(t) <= H_batt * K_batt(t)
    for t = 1:T
        row = row + 1;
        addCoef(row, idxE(t),    1);
        addCoef(row, idxK(5,t), -H_batt);
        rhs(row,1)   = 0;
        sense(row,1) = '<';
    end

    % (C11) Battery power limits: charge/discharge <= K_batt(t)
    for t = 1:T
        % Charge limit
        row = row + 1;
        addCoef(row, idxChB(t), 1);
        addCoef(row, idxK(5,t), -1);
        rhs(row,1)   = 0;
        sense(row,1) = '<';

        % Discharge limit
        row = row + 1;
        addCoef(row, idxU(5,t), 1);
        addCoef(row, idxK(5,t), -1);
        rhs(row,1)   = 0;
        sense(row,1) = '<';
    end

    % (C11b) Energy-to-power coupling: U_batt(t) <= eta_dis * E(t-1)
    row = row + 1;
    addCoef(row, idxU(5,1), 1);
    rhs(row,1)   = eta_dis * E0;
    sense(row,1) = '<';

    for t = 2:T
        row = row + 1;
        addCoef(row, idxU(5,t), 1);
        addCoef(row, idxE(t-1), -eta_dis);
        rhs(row,1)   = 0;
        sense(row,1) = '<';
    end

    % Charge limited by headroom:
    % eta_ch * ChB(t) <= H_batt * K_batt(t) - E(t-1)
    row = row + 1;
    addCoef(row, idxChB(1),  eta_ch);
    addCoef(row, idxK(5,1), -H_batt);
    rhs(row,1)   = -E0;
    sense(row,1) = '<';

    for t = 2:T
        row = row + 1;
        addCoef(row, idxChB(t),  eta_ch);
        addCoef(row, idxK(5,t), -H_batt);
        addCoef(row, idxE(t-1),  1);
        rhs(row,1)   = 0;
        sense(row,1) = '<';
    end

    % (C12) Gas must-run: U_gas(t) >= alpha * K_gas(t)  MUST RUN DILEMA
   % alpha = 0.05;
   % for t = 1:T
   %     row = row + 1;
   %     addCoef(row, idxU(3,t), 1);
   %     addCoef(row, idxK(3,t), -alpha);
   %     rhs(row,1)   = 0;
   %     sense(row,1) = '>';
   % end

    % (C12b) Nuclear must-run: U_nuc(t) >= alpha_nuc * K_nuc(t)
    alpha_nuc = 1.0;
    for t = 1:T
        row = row + 1;
        addCoef(row, idxU(1,t), 1);
        addCoef(row, idxK(1,t), -alpha_nuc);
        rhs(row,1)   = 0;
        sense(row,1) = '>';
    end

    % (C13) Smart Reserve Margin (Representative Worst-Case Hours)
    % Enforces a 20% reserve margin on firm capacity during the most critical hours of each year.
    % We select the top 10 absolute peak demand hours, and the top 10 peak demand hours when solar CF == 0.
    % Equation: K_nuclear(t) + K_gas(t) + K_coal(t) >= 1.2 * (Demand(t) - U_solar(t))
    % Rearranged: K(1,t) + K(3,t) + K(4,t) + 1.2 * U(2,t) >= 1.2 * Demand(t)
    
    reserve_margin = 1.20; 
    N_peaks = 10; % Number of critical hours to sample per category
    
    for y = 1:nYears
        % 1. Get the hour range for the current year
        rng = (y-1)*yearLen + (1:yearLen);
        
        % Extract data for the current year
        year_demand = Demand(rng);
        year_cf = cf(rng);
        
        % 2. Find the top N absolute peak demand hours
        [~, sorted_all_idx] = sort(year_demand, 'descend');
        peak_hours_all = rng(sorted_all_idx(1:N_peaks));
        
        % 3. Find the top N peak demand hours when there is NO solar (CF == 0)
        zero_cf_local_idx = find(year_cf == 0);
        [~, sorted_night_idx] = sort(year_demand(zero_cf_local_idx), 'descend');
        
        % Make sure we don't exceed array bounds if there are less than N_peaks hours without sun
        num_night_peaks = min(N_peaks, length(sorted_night_idx));
        peak_hours_night = rng(zero_cf_local_idx(sorted_night_idx(1:num_night_peaks)));
        
        % 4. Combine and remove duplicates (in case a night hour is also an absolute peak)
        critical_hours = unique([peak_hours_all, peak_hours_night]);
        
        % 5. Apply the constraint to these specific critical hours
        for t_peak = critical_hours
            row = row + 1;
            
            % Add firm capacity variables (Sources 1=Nuc, 3=Gas, 4=Coal) at t_peak
            addCoef(row, idxK(1, t_peak), 1);
            addCoef(row, idxK(3, t_peak), 1);
            addCoef(row, idxK(4, t_peak), 1);
            
            % Add solar generation (moved to LHS to balance the equation)
            addCoef(row, idxU(2, t_peak), reserve_margin);
                
            % battery power credited toward firm capacity (ELCC approximation)
            addCoef(row, idxK(5,t_peak), betaBattReserve);   
            
            % Set RHS
            rhs(row,1)   = reserve_margin * Demand(t_peak);
            
            sense(row,1) = '>';
        end
    end



    % ---------- Build model ----------
    model.A          = sparse(I, J, V, row, numVars);
    model.obj        = obj;
    model.rhs        = rhs;
    model.sense      = sense;
    model.vtype      = vtype;
    model.lb         = lb;
    model.ub         = ub;
    model.modelsense = 'min';

    % ---------- Gurobi params ----------
    params = struct();
    params.Method         = 2;    % barrier
    params.Crossover      = -1;   % auto: convert barrier result to a clean vertex solution
    params.NumericFocus   = 1;    % more careful numerics
    params.BarHomogeneous = 1;    % robust near infeasibility (low budgets)
    params.Presolve       = 2;
    params.ScaleFlag      = 1;

    params.TimeLimit     = 14400; % 2 hours (edit as needed)

    fprintf('Number of variables:   %d\n', length(model.obj));
    fprintf('Number of constraints: %d\n', size(model.A, 1));

    result = gurobi(model, params);

    % ---------- SAFE RESULT HANDLING ----------
    RES = struct();
    RES.result = result;

    % Status
    if isfield(result,'status') && ~isempty(result.status)
        RES.ResultStatus = string(result.status);
    else
        RES.ResultStatus = "UNKNOWN_STATUS";
    end

    % Gurobi runtime
    if isfield(result,'runtime') && ~isempty(result.runtime)
        RES.GurobiRuntime_sec = result.runtime;
    else
        RES.GurobiRuntime_sec = NaN;
    end

    % MIPGap (if exists)
    if isfield(result,'mipgap') && ~isempty(result.mipgap)
        RES.MIPGap = result.mipgap;
    else
        RES.MIPGap = NaN;
    end

    % Objective value (emissions) if exists
    if isfield(result,'objval') && ~isempty(result.objval)
        RES.ObjVal = result.objval;
    else
        RES.ObjVal = NaN;
    end

    runtime_sec   = toc(t_start);
    runtime_hours = runtime_sec / 3600;

    RES.runtime_sec   = runtime_sec;
    RES.runtime_hours = runtime_hours;

    % Check incumbent vector
    hasX = isfield(result,'x') && ~isempty(result.x);

    if ~hasX
        % No solution vector -> return safe NaNs (keep status/runtime/gap)
        RES.U = [];
        RES.K = [];
        RES.Z = [];
        RES.ChB = [];
        RES.Dump = [];
        RES.E = [];
        RES.C = [];

        % KPI-friendly NaNs
        RES.TotalCost_AllYears          = NaN;
        RES.TotalOPEX_AllYears          = NaN;
        RES.TotalExternalities_AllYears = NaN;
        RES.TotalCAPEX_AllYears         = NaN;
        RES.TotalEmissions_AllYears     = NaN;

        RES.TotalCost_BaseYear          = NaN;
        RES.TotalCost_TargetYear        = NaN;
        RES.OPEX_BaseYear               = NaN;
        RES.Externalities_TargetYear    = NaN;
        RES.Externalities_BaseYear      = NaN;
        RES.OPEX_TargetYear             = NaN;
        RES.CAPEX_BaseYear              = NaN;
        RES.CAPEX_TargetYear            = NaN;
        RES.Emissions_BaseYear          = NaN;
        RES.Emissions_TargetYear        = NaN;

        RES.LCOE_AllYears_NIS_per_kWh           = NaN;
        RES.LCOE_BaseYearPlus1_NIS_per_kWh      = NaN;
        RES.LCOE_TargetYear_NIS_per_kWh         = NaN;

        RES.RenewablesPct2050          = NaN;
        RES.Cap2050                    = NaN(n_sources,1);
        RES.SolarLand_km2              = NaN;

        RES.TotalDump_AllYears_MWh     = NaN;
        RES.Dump2050_MWh               = NaN;

        RES.meta = struct('n_sources', n_sources, 'T', T, 'yearLen', yearLen, 'startYr', startYr, ...
                          'maxCost', maxCost, 'maxAreaSolar', maxAreaSolar, 'maxRamp', maxRamp, ...
                          'note', "No incumbent solution vector result.x (TimeLimit/NoSolution/Infeasible).");
        return;
    end

    % ---------- Extract solution ---------
    U = zeros(n_sources, T);
    K = zeros(n_sources, T);
    Z = zeros(n_sources, T);

    for i = 1:n_sources
        U(i,:) = result.x(idxU(i,1:T));
        K(i,:) = result.x(idxK(i,1:T));
        Z(i,:) = result.x(idxZ(i,1:T));
    end

    ChB  = result.x(idxChB(1:T));
    Dump = result.x(idxDump(1:T));
    E    = result.x(idxE(1:T));
    C    = result.x(idxC(1:T));

    %%
% ---------- Post-solve totals (MATCH MODEL LOGIC) ----------
    
    CRF       = P.CRF;
    df_yearly = P.df_yearly;

    % 1. Create a year-index vector for each hour t 
    idxy_vec = ceil((1:T) / 8760); 
    
    % Initialize summation variables
    totalCAPEX      = 0;
    totalOPEX_fixed = 0;
    totalOPEX_var   = 0;
    
    % 2. Extract vintage builds Z for accurate CAPEX reporting
    Z_built = zeros(n_sources, nYears);
    for y = 1:nYears
        Z_built(:,y) = Z(:, y*8760);
    end

    totalCAPEX = 0;
    for Y = 1:nYears
        capex_payment = 0;
        for y_build = 1:Y
            % Z is in blocks, multiply by p to get MW
            mw_built = Z_built(:, y_build) .* p; 
            capex_payment = capex_payment + mw_built .* (cap(y_build, :)' .* CRF');
        end
        totalCAPEX = totalCAPEX + sum(capex_payment) * df_yearly(Y);
    end

    year_end_hours = 8760:8760:T;
    operating_hours = year_end_hours - 1; 
    num_years = length(year_end_hours);

    % 3. Calculate Fixed OPEX and Variable OPEX (Discounted)
    for i = 1:n_sources
        if i ~= 2
            hourly_fixed_cost = op(idxy_vec, i)' .* df_yearly(idxy_vec)';
            hourly_var_cost   = var(idxy_vec, i)' .* df_yearly(idxy_vec)';
            
            yearly_fixed_cost = op(1:num_years, i)' .* df_yearly(1:num_years)';
            
            totalOPEX_fixed = totalOPEX_fixed + sum(K(i, operating_hours) .* yearly_fixed_cost);
            totalOPEX_var = totalOPEX_var + sum(U(i,:) .* hourly_var_cost);
        end
    end
    
    % 3.1 Calculate Fixed OPEX for Solar (Discounted)
    yearly_fixed_cost_solar = op(1:num_years, 2)' .* df_yearly(1:num_years)';
    totalOPEX_fixed = totalOPEX_fixed + sum(K(2, operating_hours) .* yearly_fixed_cost_solar);

    % 4. Calculate Solar OPEX (Discounted)
    hourly_solar_var_cost = var(idxy_vec, 2)' .* df_yearly(idxy_vec)';
    solarOPEX_var_t = hourly_solar_var_cost .* (cf(:)' .* K(2,:));
    totalOPEX_var = totalOPEX_var + sum(solarOPEX_var_t);
    
    % 6. Calculate Externalities (Carbon Tax) (Discounted)
    totalExt = 0;
    for i = [1 3 4]
        totalExt = totalExt + sum(U(i,:) .* (c(i) * EmissionsFactor * df_yearly(idxy_vec)'));
    end
    % solar (all generation, cf*K) and battery discharge - same as in the budget constraint
    totalExt = totalExt + sum(cSolar_t(:)' .* cf(:)' .* K(2,:) .* (EmissionsFactor * df_yearly(idxy_vec)')) ...
                        + sum(cBatt_t(:)'  .* U(5,:)        .* (EmissionsFactor * df_yearly(idxy_vec)'));

    % 7. Summarize Total Costs (in Present Value)
    totalOPEX = totalOPEX_fixed + totalOPEX_var;
    totalCost_usage_build = totalOPEX + totalCAPEX + totalExt;      
    
    remainingCost = maxCost - totalCost_usage_build;

    % Solar land use
    solarArea     = areaPerSolar * K(2,:);
    maxSolarUsed  = max(solarArea);
    remainingArea = maxAreaSolar - maxSolarUsed;

    % Emissions total
    totalEmis_t  = result.objval;
    totalEmis_Mt = totalEmis_t / 1e6;

    endYr = startYr + nYears - 1;

    fprintf('\n=== SUMMARY (scenario) ===\n');
    fprintf('Horizon years           : %d to %d (%d years)\n', startYr, endYr, nYears);
    fprintf('Minimum total emissions : %.3f MtCO2e (%.0f tCO2e)\n', totalEmis_Mt, totalEmis_t);
    fprintf('Total cost (all years)  : %.3e NIS   (remaining %.3e)\n', totalCost_usage_build, remainingCost);
    fprintf('Solar land max          : %.2f km^2 (remaining %.2f km^2)\n', maxSolarUsed, remainingArea);
    fprintf('Optimization runtime    : %.2f mins (%.2f hours)\n', runtime_sec/60, runtime_hours);

    % ---------- Annual KPIs ----------
    genYear  = zeros(n_sources, nYears);
    capYear  = zeros(n_sources, nYears);
    emitYear = zeros(1, nYears);
    demYear  = zeros(1, nYears);
    areaYear = zeros(1, nYears);
    opCostYearBySource      = zeros(n_sources, nYears);
    extCostYearBySource     = zeros(n_sources, nYears);
    buildCostYearBySource   = zeros(n_sources, nYears);
    totalBuildCostPerSource = zeros(n_sources, 1);
    
    elecYear_PV = zeros(1, nYears); % To store discounted energy for LCOE calculation

    for y = 1:nYears
        rng = (y-1)*yearLen + (1:yearLen);
        demYear(y) = sum(Demand(rng));
        df = df_yearly(y); % Discount factor for this year

        % Emissions and generation
        for i = 1:n_sources
            U_y = U(i, rng);
            K_y = K(i, rng(1));
            
            genYear(i,y) = sum(U_y);
            capYear(i,y) = K_y;
            
            % Build cost per source this year (Vintage based, Annualized & Discounted)
            capex_payment = 0;
            for y_build = 1:y
                % Z is blocks. Multiply by p(i) to get MW.
                mw_built = Z_built(i, y_build) * p(i);
                capex_payment = capex_payment + mw_built * (cap(y_build, i) * CRF(i));
            end
            buildCostYearBySource(i,y) = capex_payment * df;
            totalBuildCostPerSource(i) = totalBuildCostPerSource(i) + buildCostYearBySource(i,y);

            % Annual emissions (Physical, NOT discounted)
            if i == 2
                emitYear(y) = emitYear(y) + sum(cSolar_t(rng) .* (U_y' + ChB(rng) + Dump(rng)));
            elseif i == 5
                emitYear(y) = emitYear(y) + sum(cBatt_t(rng)  .* U_y');
            else
                emitYear(y) = emitYear(y) + c(i) * sum(U_y);
            end
        end

        % OPEX by source (Discounted)
        for i = 1:n_sources
            % 1. Fixed OPEX 
            fixedOpCost = op(y, i) * capYear(i,y) * df;
            
            % 2. Variable OPEX 
            if i == 2
                varOpCost = var(y, 2) * sum(cf(rng) .* K(2, rng).') * df;
            elseif i == 5
                varOpCost = var(y, 5) * genYear(5,y) * df;
            else
                varOpCost = var(y, i) * genYear(i,y) * df;
            end
            
            opCostYearBySource(i,y) = fixedOpCost + varOpCost;
            
            % 3. Externalities (Discounted)
            if ismember(i, [1, 3, 4])
                extCost = c(i) * genYear(i,y) * EmissionsFactor * df;
            elseif i == 2
                extCost = sum(cSolar_t(rng) .* cf(rng) .* K(2, rng).') * EmissionsFactor * df;
            else
                extCost = sum(cBatt_t(rng) .* U(5, rng).') * EmissionsFactor * df;
            end
            extCostYearBySource(i,y) = extCost;
        end
        
        % Solar land usage (km^2)
        areaYear(y) = max(K(2, rng)) * areaPerSolar;
        
        % Discounted energy generation for this year (used in LCOE denominator)
        elecYear_PV(y) = sum(genYear(:,y)) * df;
    end
    % Annual energy to grid (Physical)
    elecYear = sum(genYear, 1);

    % Annual costs (Now in Present Value)
    capexYear = sum(buildCostYearBySource, 1);
    opexYear  = sum(opCostYearBySource, 1);
    ExternalitiesYear = sum(extCostYearBySource, 1);

    totalAnnualCost_actual = opexYear + capexYear + ExternalitiesYear;

    % LCOE per year (PV of Costs / PV of Energy)
    lcoeYear_MWh = totalAnnualCost_actual ./ max(1, elecYear_PV);
    lcoeYear_kWh = lcoeYear_MWh / 1000;

    % Overall System LCOE
    LCOE_AllYears_kWh = (sum(totalAnnualCost_actual) / max(1, sum(elecYear_PV))) / 1000;
    % Macro totals
    TotalCost_AllYears       = sum(totalAnnualCost_actual);
    TotalEmissions_AllYears  = sum(emitYear);
    TotalExternalities_AllYears = sum(ExternalitiesYear);
    TotalOPEX_AllYears       = sum(opexYear);
    TotalCAPEX_AllYears      = sum(capexYear);

    % Base and target indices
    BaseYear   = startYr;
    yBase      = 1;
    BaseYearP1 = BaseYear + 1;
    yBaseP1    = 2;

    yTarget = TargetYear - startYr + 1;
    if yTarget < 1 || yTarget > nYears
        yTarget = NaN;
    end

    % Base year KPIs
    Emissions_BaseYear = emitYear(yBase);
    Externalities_BaseYear = ExternalitiesYear(yBase);
    OPEX_BaseYear      = opexYear(yBase);
    CAPEX_BaseYear     = capexYear(yBase);
    TotalCost_BaseYear = totalAnnualCost_actual(yBase);

    % Target year KPIs
    if ~isnan(yTarget)
        Emissions_TargetYear = emitYear(yTarget);
        Externalities_TargetYear= ExternalitiesYear(yTarget);
        OPEX_TargetYear      = opexYear(yTarget);
        CAPEX_TargetYear     = capexYear(yTarget);
        TotalCost_TargetYear = totalAnnualCost_actual(yTarget);
        LCOE_TargetYear_kWh  = lcoeYear_kWh(yTarget);
    else
        Emissions_TargetYear = NaN;
        Externalities_TargetYear = NaN;
        OPEX_TargetYear      = NaN;
        CAPEX_TargetYear     = NaN;
        TotalCost_TargetYear = NaN;
        LCOE_TargetYear_kWh  = NaN;
    end

    % BaseYear+1 LCOE
    if nYears >= 2
        LCOE_BaseYearPlus1_kWh = lcoeYear_kWh(yBaseP1);
    else
        LCOE_BaseYearPlus1_kWh = NaN;
    end

    % 2050 shares and capacities
    y2050 = TargetYear - startYr + 1;
    
    if y2050 >= 1 && y2050 <= nYears
        rng2050 = (y2050-1)*yearLen + (1:yearLen);
    
        G_nuc  = sum(U(1, rng2050));
        G_sol  = sum(U(2, rng2050));
        G_batt = sum(U(5, rng2050));
        G_total_2050 = sum(U(:, rng2050), 'all');
    
        % RenewablesPct2050 now counts nuclear as "renewable" (per your definition)
        RenewablesPct2050 = 100 * (G_nuc + G_sol + G_batt) / max(1, G_total_2050);
    
        Cap2050 = K(:, rng2050(end));
    else
        RenewablesPct2050 = NaN;
        Cap2050           = NaN(n_sources, 1);
    end


    % Dump KPIs
    TotalDump_AllYears_MWh = sum(Dump);
    Dump2050_MWh = NaN;
    if y2050 >= 1 && y2050 <= nYears
        rng2050 = (y2050-1)*yearLen + (1:yearLen);
        Dump2050_MWh = sum(Dump(rng2050));
    end

    % ---------- Pack RES ----------
    RES.U = U;
    RES.K = K;
    RES.Z = Z;
    RES.ChB = ChB;
    RES.Dump = Dump;
    RES.E = E;
    RES.C = C;
    RES.P = P;

    RES.totalCost_usage_build = totalCost_usage_build;
    RES.remainingCost         = remainingCost;
    RES.maxSolarUsed          = maxSolarUsed;
    RES.remainingArea         = remainingArea;
    RES.totalEmissions        = totalEmis_t;

    RES.genYear  = genYear;
    RES.capYear  = capYear;
    RES.emitYear = emitYear;
    RES.demYear  = demYear;
    RES.areaYear = areaYear;

    RES.opCostYearBySource    = opCostYearBySource;
    RES.extCostYearBySource   = extCostYearBySource;
    RES.buildCostYearBySource = buildCostYearBySource;
    RES.ExternalitiesYear     = ExternalitiesYear
    RES.capexYear             = capexYear;
    RES.opexYear              = opexYear;
    RES.totalAnnualCost_actual= totalAnnualCost_actual;
    RES.elecYear              = elecYear;

    RES.lcoeYear_kWh                   = lcoeYear_kWh;
    RES.LCOE_AllYears_NIS_per_kWh      = LCOE_AllYears_kWh;
    RES.LCOE_BaseYearPlus1_NIS_per_kWh = LCOE_BaseYearPlus1_kWh;
    RES.LCOE_TargetYear_NIS_per_kWh    = LCOE_TargetYear_kWh;

    RES.TotalCost_AllYears      = TotalCost_AllYears;
    RES.TotalEmissions_AllYears = TotalEmissions_AllYears;
    RES.TotalExternalities_AllYears = TotalExternalities_AllYears;
    RES.TotalOPEX_AllYears      = TotalOPEX_AllYears;
    RES.TotalCAPEX_AllYears     = TotalCAPEX_AllYears;

    RES.BaseYear             = BaseYear;
    RES.TargetYear           = TargetYear;

    % For transparency (optional fields noted by you)
    RES.TotalCost_BaseYear   = TotalCost_BaseYear;
    RES.TotalCost_TargetYear = TotalCost_TargetYear;
    
    RES.Externalities_BaseYear = Externalities_BaseYear;
    RES.Externalities_TargetYear = Externalities_TargetYear;
    RES.OPEX_BaseYear        = OPEX_BaseYear;
    RES.OPEX_TargetYear      = OPEX_TargetYear;
    RES.CAPEX_BaseYear       = CAPEX_BaseYear;
    RES.CAPEX_TargetYear     = CAPEX_TargetYear;

    RES.Emissions_BaseYear   = Emissions_BaseYear;
    RES.Emissions_TargetYear = Emissions_TargetYear;

    RES.RenewablesPct2050    = RenewablesPct2050;
    RES.Cap2050              = Cap2050;
    RES.SolarLand_km2        = maxSolarUsed;

    RES.TotalDump_AllYears_MWh = TotalDump_AllYears_MWh;
    RES.Dump2050_MWh           = Dump2050_MWh;

    % Keep status/gap/runtime already set earlier
    RES.meta = struct( ...
        'n_sources', n_sources, ...
        'T', T, ...
        'yearLen', yearLen, ...
        'startYr', startYr, ...
        'maxCost', maxCost, ...
        'maxAreaSolar', maxAreaSolar, ...
        'maxRamp', maxRamp ...
    );

end

function addCoef(r, c, val)
    global I J V
    I(end+1) = r;
    J(end+1) = c;
    V(end+1) = val;
end
