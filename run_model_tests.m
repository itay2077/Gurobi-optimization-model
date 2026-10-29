function results = run_model_tests(level)
% RUN_MODEL_TESTS  Checks to run before starting OPT_ONE_SENS runs (CODE_VERSION 3).
%
%   results = run_model_tests(level)
%     level 1 : inputs and settings only (Excel, paths, demand path, costs)   ~1-3 min
%     level 2 : level 1 + build the LP (no solve) and check its structure     ~ model build time
%     level 3 : level 2 + solve ONE cost-min scenario and check the results   ~ one full run
%
%   The test reads the settings and inputs by executing the script's own
%   sections (BASIC CONFIG, ONE TIME INPUTS ... MODEL PARAMETERS) - so it
%   checks exactly what OPT_ONE_SENS.m will use. Put this file, OPT_ONE_SENS.m,
%   solve_opt_one_once.m and machine_paths.m in the same folder.
%
%   Output: a table with one row per test: Level, Test, Status (PASS/WARN/FAIL), Details.

    if nargin < 1, level = 1; end
    t0 = tic;
    R = cell(0, 4);                                   % {level, name, status, details}
    here = fileparts(mfilename('fullpath'));
    addpath(here);                                    % machine_paths.m / solve_opt_one_once.m must be found from any folder
    scriptFile = fullfile(here, 'OPT_ONE_SENS.m');

    fprintf('\n===== run_model_tests (level %d) =====\n', level);

    %% ---------- load settings + inputs from the script itself ----------
    try
        W = load_script_sections(scriptFile);
        R = add(R, 0, 'Script sections load (config + inputs + parameters)', 'PASS', '');
    catch ME
        R = add(R, 0, 'Script sections load (config + inputs + parameters)', 'FAIL', ME.message);
        results = finish(R, t0);
        return;
    end
    P   = W.P_common;
    yrs = W.startYr:(W.startYr + W.nYears - 1);
    yi  = @(y) y - W.startYr + 1;                     % year -> model year index

    %% ================= LEVEL 1: inputs and settings =================
    % 1.1 paths
    R = check(R, 1, 'Excel file found (machine_paths.m)', @() isfile(W.xlsFile), W.xlsFile);
    if exist('gurobi', 'file') > 0
        R = add(R, 1, 'Gurobi on the MATLAB path', 'PASS', which('gurobi'));
    elseif level >= 3
        R = add(R, 1, 'Gurobi on the MATLAB path', 'FAIL', 'gurobi.m not found - check P.gurobiPath in machine_paths.m');
    else
        R = add(R, 1, 'Gurobi on the MATLAB path', 'WARN', 'not found (needed for level 3 and for the runs)');
    end

    % 1.2 settings
    R = check(R, 1, 'CODE_VERSION = 4', @() W.CODE_VERSION == 4, sprintf('CODE_VERSION = %d', W.CODE_VERSION));
    R = check(R, 1, 'Tie-breaking cost term EPS_COST_TIEBREAK = 0.01', @() abs(W.EPS_COST_TIEBREAK - 0.01) < 1e-12, ...
        sprintf('EPS_COST_TIEBREAK = %g tCO2e per million NIS', W.EPS_COST_TIEBREAK));
    R = check(R, 1, 'Budget feasibility pre-check switched on (SKIP_INFEASIBLE_BUDGETS)', ...
        @() islogical(W.SKIP_INFEASIBLE_BUDGETS) && W.SKIP_INFEASIBLE_BUDGETS, ...
        sprintf('SKIP_INFEASIBLE_BUDGETS = %d', W.SKIP_INFEASIBLE_BUDGETS));
    % classify_budget logic (pure function, no solve)
    try
        c1 = classify_budget(380e9, 391e9, "OPTIMAL");          % below cost-min
        c2 = classify_budget(395e9, 391e9, "OPTIMAL");          % above
        c3 = classify_budget(391e9, 391e9, "OPTIMAL");          % equal -> solve
        c4 = classify_budget(395e9, NaN,   "INFEASIBLE");       % cap infeasible
        c5 = classify_budget(380e9, NaN,   "TIME_LIMIT");       % unknown -> never skip
        [~, g] = classify_budget(380e9, 400e9, "OPTIMAL");
        ok = c1 == "INFEASIBLE_BUDGET" && c2 == "RUN" && c3 == "RUN" && ...
             c4 == "INFEASIBLE_COSTMIN" && c5 == "RUN" && abs(g + 5) < 1e-9;
        R = add(R, 1, 'classify_budget: below -> skip, above/equal/unknown -> solve', pf(ok), ...
            sprintf('%s | %s | %s | %s | %s | gap %.1f%%', c1, c2, c3, c4, c5, g));
    catch ME
        R = add(R, 1, 'classify_budget: below -> skip, above/equal/unknown -> solve', 'FAIL', ['error: ' ME.message]);
    end
    R = check(R, 1, 'beta = 1 in the reserve margin', @() W.ENABLE_BETA_SWEEP && isequal(W.betaList, 1), ...
        sprintf('ENABLE_BETA_SWEEP = %d, betaList = %s', W.ENABLE_BETA_SWEEP, mat2str(W.betaList)));
    expS = [2.25 3.00 3.75 5.25 6.75];  expB = [1.50 3.00 3.00 3.75 4.50];
    R = check(R, 1, 'Build-rate schedule = approved +50% table', ...
        @() isequal(W.RAMP_SCHEDULE.solar(:,1)', [2025 2030 2035 2040 2050]) && ...
            max(abs(W.RAMP_SCHEDULE.solar(:,2)' - expS)) < 1e-9 && ...
            max(abs(W.RAMP_SCHEDULE.batt(:,2)'  - expB)) < 1e-9, ...
        sprintf('solar %s | batt %s GW/yr', mat2str(W.RAMP_SCHEDULE.solar(:,2)'), mat2str(W.RAMP_SCHEDULE.batt(:,2)')));

    % 1.3 retirement / legacy capacity
    if ~W.ENABLE_RETIREMENT
        R = add(R, 1, 'Retirement switched on', 'WARN', 'ENABLE_RETIREMENT = false (version-2 behaviour, validation only)');
    else
        L = P.legacyYear;
        ok = L(4, yi(2029)) == 5600 && L(4, yi(2030)) == 0 && ...
             L(3, yi(2039)) == 11700 && L(3, yi(2040)) == 3700 && ...
             L(5, yi(2042)) == 369 && L(5, yi(2043)) == 0 && ...
             all(L(2,:) == 5900) && all(L(1,:) == 0);
        R = add(R, 1, 'Legacy schedule: coal out 1.1.2030, 8 GW gas out 1.1.2040, batt out 1.1.2043', ...
            pf(ok), sprintf('coal 2029/2030 = %g/%g, gas 2039/2040 = %g/%g, batt 2042/2043 = %g/%g MW', ...
            L(4,yi(2029)), L(4,yi(2030)), L(3,yi(2039)), L(3,yi(2040)), L(5,yi(2042)), L(5,yi(2043))));
    end
    R = check(R, 1, 'Lifetimes [nuc solar gas coal batt] = [60 30 30 30 20]', ...
        @() isequal(P.lifeTime(:)', [60 30 30 30 20]), mat2str(P.lifeTime(:)'));

    % 1.4 demand
    D = W.Demand(:);
    R = check(R, 1, 'Demand: 245,280 hours, finite and positive', ...
        @() numel(D) == 245280 && all(isfinite(D)) && all(D > 0), sprintf('%d values, min %.0f MW', numel(D), min(D)));
    ann = zeros(1, W.nYears);
    for y = 1:W.nYears, ann(y) = sum(D((y-1)*W.yearLen + (1:W.yearLen))); end
    g   = 0.031 * (yrs <= 2030) + 0.037 * (yrs > 2030 & yrs <= 2040) + 0.028 * (yrs > 2040);
    tgt = ann(1) * cumprod([1, 1 + g(2:end)]);
    if W.DC_FLAT_MW > 0
        R = add(R, 1, 'Demand follows the Noga 2022 path', 'WARN', 'DC_FLAT_MW > 0 - path check skipped');
    else
        err = max(abs(ann ./ tgt - 1));
        det = sprintf('TWh 2023/2030/2040/2050 = %.1f / %.1f / %.1f / %.1f (expected %.1f / %.1f / %.1f / %.1f), max dev %.3f%%, DEMAND_PATH = ''%s''', ...
            ann(1)/1e6, ann(yi(2030))/1e6, ann(yi(2040))/1e6, ann(end)/1e6, ...
            tgt(1)/1e6, tgt(yi(2030))/1e6, tgt(yi(2040))/1e6, tgt(end)/1e6, 100*err, W.DEMAND_PATH);
        if strcmp(W.DEMAND_PATH, 'excel')
            R = add(R, 1, 'Excel demand follows the Noga 2022 path (3.1/3.7/2.8 %)', pf(err < 1e-3), det);
        else
            R = add(R, 1, 'Demand follows the Noga 2022 path (rescaled in code)', ...
                pf(err < 1e-3 || ~strcmp(W.DEMAND_PATH, 'noga2022')), det);
        end
    end
    R = check(R, 1, 'Demand 2023 = 77.6 TWh (+/- 0.5)', @() abs(ann(1)/1e6 - 77.6) < 0.5, sprintf('%.2f TWh', ann(1)/1e6));
    if W.DC_FLAT_MW == 0
        r = D((W.nYears-1)*W.yearLen + (1:W.yearLen)) ./ D(1:W.yearLen);
        R = check(R, 1, 'Hourly shape identical in 2023 and 2050', @() (max(r) - min(r)) / mean(r) < 1e-6, ...
            sprintf('2050/2023 ratio %.4f - %.4f', min(r), max(r)));
    end
    peak = max(D(1:W.yearLen));
    R = add(R, 1, 'Info: peak demand 2023 / 2050', 'PASS', sprintf('%.0f / %.0f MW', peak, max(D(end-W.yearLen+1:end))));

    % 1.5 solar capacity factor
    cf1 = W.cf_single(:);
    R = check(R, 1, 'Solar CF: 8760 values in [0,1], annual yield 1600-1800 MWh/MW', ...
        @() numel(cf1) == 8760 && all(cf1 >= 0 & cf1 <= 1) && sum(cf1) > 1600 && sum(cf1) < 1800, ...
        sprintf('%d values, yield %.0f MWh/MW, CF %.1f%%', numel(cf1), sum(cf1), 100*mean(cf1)));

    % 1.6 cost tables
    % The model reads the cost rows BY POSITION (row 1 = 2023 ... row 28 = 2050).
    % Rows below 2050 (e.g. a 2050 target and a decline factor) are allowed but not used.
    C28 = [W.capMatrix(1:28,:); W.opMatrix(1:28,:); W.varMatrix(1:28,:)];
    okC = size(W.capMatrix,1) >= 28 && size(W.opMatrix,1) >= 28 && size(W.varMatrix,1) >= 28 && ...
          isequal(W.years(1:28)', 2023:2050) && all(isfinite(C28(:))) && all(C28(:) >= 0);
    R = add(R, 1, 'Cost sheets: rows 1-28 = 2023-2050, 5 sources, finite, non-negative', pf(okC), ...
        sprintf('capex %s, opex %s, var %s rows read; rows 29+ are ignored by the model', ...
        mat2str(size(W.capMatrix)), mat2str(size(W.opMatrix)), mat2str(size(W.varMatrix))));

    % 1.7 battery capex: 2023-2025 calibrated to BNEF turnkey prices, NZO path from 2026
    %     2023: ~$275/kWh x 3.69  = 1,015 NIS/kWh -> 4,059,000 NIS/MW (BNEF 2024 survey: 2024 was 40% below 2023)
    %     2024:  $165/kWh x 3.700 =   610 NIS/kWh -> 2,442,000 NIS/MW (BNEF ESS Cost Survey 2024)
    %     2025:  $110/kWh x 3.452 =   380 NIS/kWh -> 1,519,000 NIS/MW (BNEF ESS Cost Survey 2025, 4-h systems)
    %     2026 on: NZO (2021) path, 1,231,729 NIS/MW in 2026 -> 800,000 NIS/MW in 2050
    expCap = [4059000 2442000 1519000 1231729];
    gotCap = W.capMatrix(1:4, 5)';
    okCap  = all(abs(gotCap ./ expCap - 1) < 0.005) && abs(W.capMatrix(28,5) / 800000 - 1) < 0.005;
    R = add(R, 1, 'Battery capex: BNEF 2023-2025, NZO path from 2026', pf(okCap), ...
        sprintf('2023-2026 = %s NIS/MW (expected %s), 2050 = %.0f', mat2str(round(gotCap)), mat2str(expCap), W.capMatrix(28,5)));
    R = add(R, 1, 'Info: battery fixed O&M as share of capex 2023 / 2025 / 2050', 'PASS', ...
        sprintf('%.1f%% / %.1f%% / %.1f%% (NZO 57,400 NIS/MW-yr; NREL 2025 uses 4%%)', ...
        100*W.opMatrix(1,5)/W.capMatrix(1,5), 100*W.opMatrix(3,5)/W.capMatrix(3,5), 100*W.opMatrix(28,5)/W.capMatrix(28,5)));

    % 1.8 emission factors and discounting
    R = check(R, 1, 'PV and storage emission factors: 28 finite positive values', ...
        @() numel(W.cSolar_year) == 28 && numel(W.cBatt_year) == 28 && all(isfinite([W.cSolar_year(:); W.cBatt_year(:)])) && all([W.cSolar_year(:); W.cBatt_year(:)] > 0), ...
        sprintf('PV %.4f -> %.4f, storage %.4f -> %.4f t/MWh', W.cSolar_year(1), W.cSolar_year(end), W.cBatt_year(1), W.cBatt_year(end)));
    R = check(R, 1, 'Discount factors: 28 years, 2023 = 1, r = 6%', ...
        @() numel(P.df_yearly) == 28 && P.df_yearly(1) == 1 && abs(P.r - 0.06) < 1e-12, sprintf('df(2050) = %.4f', P.df_yearly(end)));

    if level < 2, results = finish(R, t0); return; end

    %% ================= LEVEL 2: build the LP, check its structure =================
    fprintf('\nBuilding the LP (no solve) ...\n');
    maxRamp = [3 * W.ENABLE_NUCLEAR * P.p(1); W.solarRampList(1) * P.p(2); 50 * P.p(3); 0; W.battRampList(1) * P.p(5)];
    maxArea = W.areaList(1);
    maxCost = W.budgetList(1);
    PB = P; PB.BUILD_ONLY = true;
    try
        tb = tic;
        B  = solve_opt_one_once(maxCost, maxArea, maxRamp, W.betaList(1), PB);
        M  = B.model;  A = M.A;
        R  = add(R, 2, 'LP builds', 'PASS', sprintf('%d rows x %d columns, %d nonzeros, %.1f min', size(A,1), size(A,2), nnz(A), toc(tb)/60));
    catch ME
        R = add(R, 2, 'LP builds', 'FAIL', ME.message);
        results = finish(R, t0);
        return;
    end
    T = W.T; n = P.n_sources; yl = W.yearLen;
    idxU = @(i,t) (i-1)*T + t;
    idxZ = @(i,t) n*T + (i-1)*T + t;
    idxK = @(i,t) 2*n*T + (i-1)*T + t;
    idxC = @(t) 3*n*T + 3*T + t;

    R = check(R, 2, 'Model is an LP (all variables continuous)', @() all(M.vtype == 'C'), '');
    R = check(R, 2, 'Land constraint: one row per year (+ first hour)', ...
        @() numel(B.landRows) == W.nYears + 1 && all(M.rhs(B.landRows) == maxArea), ...
        sprintf('%d rows, rhs %g km2', numel(B.landRows), maxArea));

    % C3 rows (capacity dynamics) at the legacy retirement hours
    c3 = @(i,t) intersect(find(A(:, idxK(i,t)) == 1), find(A(:, idxK(i,t-1)) == -1));
    tests = { 4, 7*yl,  -5600, 'coal out at end of 2029'; ...
              4, 8*yl,      0, 'coal: nothing at end of 2030'; ...
              3, 17*yl, -8000, 'gas -8 GW at end of 2039'; ...
              5, 20*yl,  -369, 'legacy battery out at end of 2042'};
    for k = 1:size(tests,1)
        rr = c3(tests{k,1}, tests{k,2});
        ok = numel(rr) == 1 && abs(M.rhs(rr) - tests{k,3}) < 1e-6;
        got = NaN; if numel(rr) == 1, got = M.rhs(rr); end
        R = add(R, 2, ['C3 legacy step: ' tests{k,4}], pf(ok), sprintf('rhs = %g (expected %g)', got, tests{k,3}));
    end

    % new-build retirement link: battery built end of 2023 leaves at end of 2043
    rr = c3(5, 21*yl);
    ok = numel(rr) == 1 && abs(A(rr, idxZ(5, yl)) - P.p(5)) < 1e-9;
    R = add(R, 2, 'C3 retirement: battery built 2023 retires after 20 years', pf(ok), '');
    nzB = nnz(A(:, idxZ(5, yl)));  nzG = nnz(A(:, idxZ(3, yl)));
    R = add(R, 2, 'Z columns: battery 2023 build in 4 rows, gas 2023 build in 3 rows', pf(nzB == 4 && nzG == 3), ...
        sprintf('battery %d, gas %d (build, [retire], capex, build limit)', nzB, nzG));

    % build-rate limit on Z (C8)
    rowsZ = find(A(:, idxZ(5, yl)));
    lim5  = min(maxRamp(5), P.rampYear(5,1));
    ok = any(M.sense(rowsZ) == '<' & abs(M.rhs(rowsZ) - lim5) < 1e-6);
    R = add(R, 2, 'C8 build limit on batteries in 2023', pf(ok), sprintf('expected %g MW', lim5));
    rowsZc = find(A(:, idxZ(4, yl)));
    ok = any(M.sense(rowsZc) == '<' & M.rhs(rowsZc) == 0);
    R = add(R, 2, 'C8: no new coal (limit 0)', pf(ok), '');

    % CAPEX annuity truncated at the lifetime (C7 row at t = 8760)
    rowC7 = find(A(:, idxC(yl)) == 1);
    for src = [5 3]
        yLast = min(W.nYears, 1 + P.lifeTime(src) - 1);
        expv  = -(W.capMatrix(1,src) / 1e6) * P.p(src) * P.CRF(src) * sum(P.df_yearly(1:yLast));
        got   = full(A(rowC7, idxZ(src, yl)));
        ok    = numel(rowC7) == 1 && abs(got / expv - 1) < 1e-9;
        R = add(R, 2, sprintf('C7 capex annuity for source %d paid for %d years', src, yLast), pf(ok), ...
            sprintf('coef %.6g (expected %.6g)', got, expv));
    end

    % demand balance rhs (C1) at first and last hour
    for t = [1 T]
        rr = find(A(:, idxU(3,t)) == 1);
        ok = any(M.sense(rr) == '=' & abs(M.rhs(rr) - D(t)) < 1e-6);
        R = add(R, 2, sprintf('C1 demand balance rhs at hour %d', t), pf(ok), sprintf('%.1f MW', D(t)));
    end

    % budget as a bound on C(T), tie-breaking term in the objective
    if strcmp(P.OBJECTIVE, 'emissions')
        R = check(R, 2, 'Objective: tie-breaking coefficient on C(T) = EPS_COST', ...
            @() abs(M.obj(idxC(T)) - P.EPS_COST) < 1e-12 && nnz(M.obj(idxC(1:T-1))) == 0, ...
            sprintf('obj(C(T)) = %g', full(M.obj(idxC(T)))));
        R = check(R, 2, 'Budget = upper bound on C(T)', @() abs(M.ub(idxC(T)) - maxCost/1e6) < 1e-6, sprintf('%g million NIS', M.ub(idxC(T))));
    end
    clear A M B

    if level < 3, results = finish(R, t0); return; end

    %% ================= LEVEL 3: solve one cost-min scenario =================
    fprintf('\nSolving one cost-min scenario (land %g km2) - this takes as long as a normal run ...\n', maxArea);
    PS = P; PS.BUILD_ONLY = false; PS.OBJECTIVE = 'cost';
    try
        ts  = tic;
        RES = solve_opt_one_once(1e13, maxArea, maxRamp, W.betaList(1), PS);
        st  = string(RES.ResultStatus);
        R   = add(R, 3, 'Solve status OPTIMAL', pf(st == "OPTIMAL"), sprintf('%s, %.1f min', st, toc(ts)/60));
    catch ME
        R = add(R, 3, 'Solve', 'FAIL', ME.message);
        results = finish(R, t0);
        return;
    end
    if isempty(RES.U)
        R = add(R, 3, 'Solution vector', 'FAIL', 'no solution returned');
        results = finish(R, t0);
        return;
    end
    res = max(abs(sum(RES.U, 1)' - D));
    R = add(R, 3, 'Demand met every hour', pf(res < 1), sprintf('max |supply - demand| = %.3g MW', res));
    t30 = yi(2030); rng30 = (t30-1)*yl + 1 : T;
    R = add(R, 3, 'No coal capacity or generation from 2030', pf(max(RES.K(4, rng30)) < 1e-6 && sum(RES.U(4, rng30)) < 1e-3), ...
        sprintf('max K = %.3g MW, generation = %.3g MWh', max(RES.K(4, rng30)), sum(RES.U(4, rng30))));
    R = add(R, 3, 'Gas capacity in 2050 >= 3.7 GW legacy', pf(RES.K(3, end) >= 3700 - 1e-6), sprintf('%.0f MW', RES.K(3, end)));
    R = add(R, 3, 'Land within the cap', pf(RES.SolarLand_km2 <= maxArea + 1e-3), sprintf('%.1f of %g km2', RES.SolarLand_km2, maxArea));
    rel = abs(RES.TotalCost_AllYears / (RES.C(end) * 1e6) - 1);
    R = add(R, 3, 'Post-solve cost = model cost C(T) (capex truncation consistent)', pf(rel < 1e-4), ...
        sprintf('post %.6e vs model %.6e NIS (%.2e rel)', RES.TotalCost_AllYears, RES.C(end)*1e6, rel));
    cmv = RES.TotalCost_AllYears;
    ok  = classify_budget(0.99*cmv, cmv, RES.ResultStatus) == "INFEASIBLE_BUDGET" && ...
          classify_budget(1.01*cmv, cmv, RES.ResultStatus) == "RUN";
    R = add(R, 3, 'Pre-check on this cost-min: budget -1% skipped, +1% solved', pf(ok), sprintf('cost-min %.4g bn NIS', cmv/1e9));
    R = add(R, 3, 'Land shadow prices returned', pf(any(isfinite(RES.Dual_Land_year))), ...
        sprintf('sum %.4g million NIS/km2, land full in %g', RES.Dual_Land_Sum, RES.LandFullYear));
    R = add(R, 3, 'Info: 2050 capacities [nuc solar gas coal batt] GW', 'PASS', mat2str(round(RES.Cap2050(:)'/1e3, 1)));
    R = add(R, 3, 'Info: RE share 2050 / total cost', 'PASS', sprintf('%.1f%% / %.4g billion NIS', RES.RenewablesPct2050, RES.TotalCost_AllYears/1e9));

    results = finish(R, t0);
end

%% ===================== helpers =====================
function W = load_script_sections(scriptFile)
% Execute the script's BASIC CONFIG and ONE TIME INPUTS ... MODEL PARAMETERS
% sections in this workspace and return all variables in a struct.
    fid = fopen(scriptFile, 'r', 'n', 'UTF-8');
    if fid < 0, error('Cannot open %s', scriptFile); end
    txt = fread(fid, '*char')';
    fclose(fid);
    txt = strrep(txt, char(13), '');
    b1 = cut(txt, '%% ---------- BASIC CONFIG', '%% ---------- OUTDIR SELECTION');
    b2 = cut(txt, '%% ---------- ONE TIME INPUTS', '%% ---------- BUILD SCENARIOS');
    tmp = fullfile(tempdir, ['oos_tests_tmp_' char(randi([97 122], 1, 8)) '.m']);
    fid = fopen(tmp, 'w', 'n', 'UTF-8');
    fprintf(fid, '%s\n%s\n', b1, b2);
    fclose(fid);
    cleanup = onCleanup(@() delete(tmp));
    run(tmp);
    vars = who;
    W = struct();
    for k = 1:numel(vars)
        if ~ismember(vars{k}, {'txt','b1','b2','tmp','fid','cleanup','vars','k','W','scriptFile'})
            W.(vars{k}) = eval(vars{k});
        end
    end
end

function s = cut(txt, a, b)
    ia = strfind(txt, a);  ib = strfind(txt, b);
    if isempty(ia) || isempty(ib), error('Section markers not found: "%s" / "%s"', a, b); end
    s = txt(ia(1):ib(1)-1);
end

function R = add(R, lvl, name, status, details)
    R(end+1, :) = {lvl, name, status, details};
    fprintf('[%s] L%d  %s', status, lvl, name);
    if ~isempty(details), fprintf('  |  %s', details); end
    fprintf('\n');
end

function R = check(R, lvl, name, fn, details)
    try
        ok = fn();
        R = add(R, lvl, name, pf(ok), details);
    catch ME
        R = add(R, lvl, name, 'FAIL', ['error: ' ME.message]);
    end
end

function s = pf(ok)
    if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function results = finish(R, t0)
    results = cell2table(R, 'VariableNames', {'Level', 'Test', 'Status', 'Details'});
    nF = sum(strcmp(results.Status, 'FAIL'));  nW = sum(strcmp(results.Status, 'WARN'));
    fprintf('\n===== %d tests: %d PASS, %d WARN, %d FAIL  (%.1f min) =====\n', ...
        height(results), height(results) - nF - nW, nW, nF, toc(t0)/60);
    if nF > 0
        fprintf('Do NOT start the runs until the FAIL items are fixed.\n');
    end
end
