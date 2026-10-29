%% ============================================================
%  OPT_ONE_SENS.m  - Batch runner for OPT ONE model
%  - Builds a grid of scenarios (ramp, budget, area)
%  - For each scenario:
%       * Runs an LP optimization with Gurobi (min emissions with cost and land
%         limits, or min cost when OBJECTIVE = 'cost')
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
%
%  CODE_VERSION 3 (paper model) - changes vs. version 2:
%   (1) Demand path: Noga 2022 long-term forecast, set in the Excel (DEMAND_PATH = 'excel');
%       code options for sensitivities and an optional flat data-centre load
%   (2) Retirement: legacy capacity follows LEGACY_RETIRE (coal out from
%       1.1.2030, 8.0 GW legacy gas out from 1.1.2040), new builds retire after
%       lifeTime, CAPEX annuity paid only over the asset lifetime
%   (3) Land constraint (C6) written once per year instead of once per hour
%   (4) Build-rate limit (C8) applied to new builds Z instead of the net change in K
%   (5) Shadow prices saved: land (per year) and budget
%   (6) Paths taken only from machine_paths.m; build-rate schedule +50%
%   (7) Solver moved to solve_opt_one_once.m (so run_model_tests.m can call it)
%  CODE_VERSION 4: (8) tie-breaking cost term EPS_COST_TIEBREAK in the emissions
%       objective (see BASIC CONFIG); budget shadow price corrected for it
%% ============================================================

clear; clc;
t_batch = tic;

%% ---------- BASIC CONFIG ----------
MP = machine_paths();        % per-computer paths (lab PC / personal PC)
runsRoot = MP.runsRoot;
xlsFile  = MP.xlsFile;
addpath(MP.gurobiPath);
scriptName = 'OPT_ONE_SENS';

% Scenario lists (edit as needed)
solarRampList = [150];   % x100 MW/yr = 15 GW/yr; non-binding cap, RAMP_SCHEDULE is the real limit
battRampList  = [150];
areaList   = [400 500 600 700 800 900 1000];                  % km2; ~905 km2 = max solar the build-rate schedule allows, 1000 = land not binding
budgetList = [382.5 385 387.5 390 392.5 395 400 410 425 440] * 1e9;   % NIS. Dense where emissions fall steeply.
% Cost-min (run A, v3): 391.1 (400 km2), 387.0 (500), 384.1 (600), 382.7 (700), 382.5 (800-1000) bn NIS.
% Reference scenario (separate run): areaList = [100], budgetList = 440e9 (cost-min at 100 km2 = 436.6 bn).
% Budgets below a cap's cost-min are INFEASIBLE by design and are kept (they are results too).
ENABLE_NUCLEAR = false; % true = allow 3 GW nuclear (built end of 2042)
ENABLE_BETA_SWEEP  = true;              % true = sweep battery-ELCC credit in the reserve margin (C13)
betaList_onEnabled = [1];  % paper runs: beta = 1 (discussed in the paper, not swept in the main grid)
RE_TARGET_2050 = 0;     % minimum renewable share in 2050 (0-1); fossil (gas + coal) <= 1 - target. 0 = no constraint

if ENABLE_BETA_SWEEP
    betaList = betaList_onEnabled;
else
    betaList = 0;                        % baseline: battery gets no credit in C13 (today's behaviour)
end
% ---- time-varying build-rate limits [year GW/yr]; set RAMP_SCHEDULE = [] for constant limits ----
% Optimistic schedule = 1.5 x the reference schedule. Reference anchored on:
% 2025 record additions (~1.3-1.4 GW), 2030 target 16 GW RE, 2035 plan 26 GW RE,
% storage >9 GW by 2030 (Electricity Authority), 250-320 W/capita/yr (NL 2023, UAE 2023).
% Values are linearly interpolated between the anchor years; 2023-2024 take the 2025 value.
RAMP_SCHEDULE.solar = [2025 2.25; 2030 3.00; 2035 3.75; 2040 5.25; 2050 6.75];
RAMP_SCHEDULE.batt  = [2025 1.50; 2030 3.00; 2035 3.00; 2040 3.75; 2050 4.50];

% ---- demand path (applied to the hourly profile read from the Excel) ----
% 'excel'         : the Excel column J as is. BASE CASE - the Excel holds the Noga 2022 path
%                   (sheet 'חישוב אחוזים', row 18: x1.031 to 2030, x1.037 2031-40, x1.028 2041-50).
%                   run_model_tests.m checks that the Excel matches this path.
% 'noga2022'      : rescale in code to the Noga 2022 path (same result as a correct Excel; cross-check)
% 'noga2026_low'  : 2.71%/yr from the 2023 Excel value (Noga 2026 low, press-reported; sensitivity)
% 'noga2026_high' : 3.84%/yr from the 2023 Excel value (Noga 2026 high, press-reported; sensitivity)
DEMAND_PATH   = 'excel';
DC_FLAT_MW    = 0;       % extra flat load (data centres) in MW; 0 = off
DC_START_YEAR = 2030;    % first year of the extra flat load

% ---- retirement ----
% ENABLE_RETIREMENT = false reproduces version 2 (no retirement, annuity to 2050).
% LEGACY_RETIRE rows: [MW  lastYearInService]; Inf = stays to 2050.
% Order: 1 Nuclear, 2 Solar, 3 Gas, 4 Coal, 5 Battery. Rows of each source must sum to init_cap.
ENABLE_RETIREMENT = true;
LEGACY_RETIRE = { ...
    zeros(0,2), ...                 % nuclear: none
    [5900 Inf], ...                 % solar: assumed installed ~2020 -> 30 yr -> beyond 2050
    [8000 2039; 3700 Inf], ...      % gas: legacy IEC units out from 1.1.2040; IPP units stay
    [5600 2029], ...                % coal: out from 1.1.2030
    [369 2042] };                   % battery: installed ~2022 -> 20 yr -> out from 1.1.2043

OBJECTIVE      = 'emissions';    % 'emissions' (current model) | 'cost' (economic minimum)

% ---- tie-breaking cost term (emissions objective only) ----
% Objective = total emissions [tCO2e] + EPS_COST_TIEBREAK * C(T) [million NIS].
% Why: once the budget no longer binds, many solutions have the same minimum
% emissions and the LP picks an arbitrary one (e.g. 77 GW of idle gas that just
% spends the budget). The small cost term makes the solver choose the cheapest
% of the minimum-emission solutions, so reported capacities and costs are real.
% Why 0.01 tCO2e per million NIS:
%   * The model would give up 1 t of abatement only to save 100 million NIS
%     (1/0.01), far above any real abatement cost -> emissions are unaffected.
%   * Upper bound on the change in emissions: 0.01 x ~4e5 million NIS of total
%     cost = 4,000 t, i.e. < 0.001% of ~670 Mt (~0.8 million NIS at 200 NIS/t).
%   * Not smaller: barrier converges to ~1e-8 of the objective (~7 t). With
%     0.01, wasting 50 bn NIS shows up as 500 t, well above that noise; with
%     1e-4 it would be 5 t, inside the noise, and ties would stay arbitrary.
% Set to 0 to recover the pure emissions objective (version 3 behaviour).
EPS_COST_TIEBREAK = 0.01;   % tCO2e per million NIS
CARBON_PRICE   = 200;       % NIS/tCO2e inside the cost (0 = direct-cost minimum)
if strcmp(OBJECTIVE, 'cost')
    budgetList = 1e13;      % effectively unconstrained (one run per land cap)
end
% ---- run registry ----
CODE_VERSION    = 4;   % bump ONLY when a code/data change alters the results (4 = tie-breaking cost term)
RUN_TAG         = 'main_grid_v4';  % optional short tag added to the run folder name
RUN_DESCRIPTION = 'Main grid v4: emission-min, 7 land caps x 10 budgets, no nuclear';  % one sentence: what this run is for
TEST_CELLS      = [];  % moved here from BUILD SCENARIOS
% Paths (runsRoot, xlsFile, Gurobi) come only from machine_paths.m - edit them there.



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
            regCfg = struct();
            regCfg.REG_ROOT          = fullfile(runsRoot, scriptName);
            regCfg.CODE_VERSION      = CODE_VERSION;
            regCfg.RUN_TAG           = RUN_TAG;
            regCfg.RUN_DESCRIPTION   = RUN_DESCRIPTION;
            regCfg.OBJECTIVE         = OBJECTIVE;
            regCfg.EPS_COST_TIEBREAK = EPS_COST_TIEBREAK;
            regCfg.ENABLE_NUCLEAR    = ENABLE_NUCLEAR;
            regCfg.ENABLE_BETA_SWEEP = ENABLE_BETA_SWEEP;
            regCfg.betaList          = betaList;
            regCfg.budgetList        = budgetList;
            regCfg.areaList          = areaList;
            regCfg.solarRampList     = solarRampList;
            regCfg.battRampList      = battRampList;
            regCfg.RAMP_SCHEDULE     = RAMP_SCHEDULE;
            regCfg.CARBON_PRICE      = CARBON_PRICE;
            regCfg.TEST_CELLS        = TEST_CELLS;
            regCfg.codeFile          = [mfilename('fullpath') '.m'];
            regCfg.dataFile          = xlsFile;
            regCfg.RE_TARGET_2050    = RE_TARGET_2050;
            regCfg.DEMAND_PATH       = DEMAND_PATH;
            regCfg.DC_FLAT_MW        = DC_FLAT_MW;
            regCfg.DC_START_YEAR     = DC_START_YEAR;
            regCfg.ENABLE_RETIREMENT = ENABLE_RETIREMENT;
            regCfg.LEGACY_RETIRE     = LEGACY_RETIRE;
            outDir = registry('new_run', regCfg);
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
runInfo = registry('load_run', outDir);   % [] for runs created before the registry

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
sheetName = 'ROTH 1.0';
rangeDem  = 'J6:J245285';        % Demand
startYr   = 2023;
yearLen   = 8760;
sheetCapex= 'capex';
sheetOpex= 'opex';
sheetVarOpex= 'var-opex';

Demand = readmatrix(xlsFile, 'Sheet', sheetName, 'Range', rangeDem);   % no Excel/COM needed (was xlsread)
Demand = Demand(:);
T      = numel(Demand);
nYears = floor(T / yearLen);

% ---- rescale annual totals to the selected demand path (hourly shape unchanged) ----
yrsD   = startYr:(startYr + nYears - 1);
annExcel = zeros(1, nYears);
for y = 1:nYears
    annExcel(y) = sum(Demand((y-1)*yearLen + (1:yearLen)));
end
switch DEMAND_PATH
    case 'excel'
        gD = [];
    case 'noga2022'
        gD = 0.031 * (yrsD <= 2030) + 0.037 * (yrsD > 2030 & yrsD <= 2040) + 0.028 * (yrsD > 2040);
    case 'noga2026_low'
        gD = 0.0271 * ones(1, nYears);
    case 'noga2026_high'
        gD = 0.0384 * ones(1, nYears);
    otherwise
        error('Unknown DEMAND_PATH: %s', DEMAND_PATH);
end
annTarget = annExcel;
if ~isempty(gD)
    for y = 2:nYears
        annTarget(y) = annTarget(y-1) * (1 + gD(y));   % growth of year y applied to year y-1
    end
end
for y = 1:nYears
    rngD = (y-1)*yearLen + (1:yearLen);
    Demand(rngD) = Demand(rngD) * (annTarget(y) / annExcel(y));
    if DC_FLAT_MW > 0 && yrsD(y) >= DC_START_YEAR
        Demand(rngD) = Demand(rngD) + DC_FLAT_MW;
    end
end
fprintf('Demand path ''%s'' (+%g MW flat from %d): TWh in 2023/2030/2040/2050 = ', DEMAND_PATH, DC_FLAT_MW, DC_START_YEAR);
for yy = [2023 2030 2040 2050]
    fprintf('%.1f ', sum(Demand((yy-startYr)*yearLen + (1:yearLen))) / 1e6);
end
fprintf('\n');

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
P_common.EPS_COST        = EPS_COST_TIEBREAK;   % tCO2e per million NIS (emissions objective only)
P_common.EmissionsFactor = CARBON_PRICE;      % replaces the fixed 200
P_common.RE_TARGET_2050  = RE_TARGET_2050;

% Order: [1 Nuclear; 2 Solar; 3 Gas; 4 Coal; 5 Battery]
P_common.n_sources  = 5;
P_common.init_cap   = [0;5900;11700;5600;369];        % MW (must match LEGACY_RETIRE)
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

% ---- legacy (existing) capacity available in each model year [MW] ----
P_common.ENABLE_RETIREMENT = ENABLE_RETIREMENT;
yrsL = startYr:(startYr + nYears - 1);
P_common.legacyYear = zeros(P_common.n_sources, nYears);
for i = 1:P_common.n_sources
    tr = LEGACY_RETIRE{i};
    assert(abs(sum(tr(:,1)) - P_common.init_cap(i)) < 1e-6, ...
        'LEGACY_RETIRE for source %d does not sum to init_cap', i);
    for r = 1:size(tr,1)
        if ENABLE_RETIREMENT
            P_common.legacyYear(i,:) = P_common.legacyYear(i,:) + tr(r,1) * (yrsL <= tr(r,2));
        else
            P_common.legacyYear(i,:) = P_common.legacyYear(i,:) + tr(r,1);
        end
    end
end
disp('Legacy capacity [GW] in 2023, 2029, 2030, 2039, 2040, 2043, 2050 (rows: Nuc, Solar, Gas, Coal, Batt):');
disp(round(P_common.legacyYear(:, [2023 2029 2030 2039 2040 2043 2050] - startYr + 1) / 1e3, 2));
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
                     if isempty(runInfo)   % old run folder (resume only): keep the old names
                         scName = sprintf('S%03d_Sol%03d_Bat%03d_B%.1f_A%d', sid, s, b, B/1e11, A);
                         if ENABLE_BETA_SWEEP
                             scName = sprintf('%s_Beta%.1f', scName, beta);
                         end
                     else
                         scName = registry('scenario_name', runInfo, sid, B, A, beta, ENABLE_BETA_SWEEP);
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

        % Shadow prices and land exhaustion
        Dual_Land_Sum             = RES.Dual_Land_Sum;
        Dual_Budget               = RES.Dual_Budget;
        LandFullYear              = RES.LandFullYear;

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
        Dual_Land_Sum, Dual_Budget, LandFullYear, ...
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
            'Dual_Land_Sum','Dual_Budget','LandFullYear', ...
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
%% ---------- UPDATE THE VERSION INDEX ----------
if ~isempty(runInfo)
    try
        registry('rebuild', runInfo.version, fullfile(runsRoot, scriptName));
    catch ME
        warning('Index not updated: %s', ME.message);
    end
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

% The solver (solve_opt_one_once) and addCoef live in solve_opt_one_once.m
