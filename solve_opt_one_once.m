% SOLVE_OPT_ONE_ONCE  Build and solve one scenario of the OPT ONE LP (CODE_VERSION 3).
%   RES = solve_opt_one_once(maxCost, maxAreaSolar, maxRamp, betaBattReserve, P)
%   P is P_common built in OPT_ONE_SENS.m. With P.BUILD_ONLY = true the
%   model is built and returned in RES.model without calling Gurobi.
%   Called by OPT_ONE_SENS.m and by run_model_tests.m.
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
    legacyYear    = P.legacyYear;          % legacy capacity per year [MW]
    retireOn      = P.ENABLE_RETIREMENT;   % new builds retire after lifeTime, annuity truncated

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

    % Tie-breaking cost term (emissions objective only); explained in OPT_ONE_SENS.m BASIC CONFIG
    epsCost = 0;
    if isfield(P, 'EPS_COST') && strcmp(P.OBJECTIVE, 'emissions')
        epsCost = P.EPS_COST;               % tCO2e per million NIS
        obj(idxC(T)) = epsCost;
    end

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

    % (C3) Capacity dynamics with retirement
    %   K(i,t) = K(i,t-1) + p*Z(i,t) - p*Z(i,t-L_i*8760) + [legacy(y+1) - legacy(y)]
    % Builds, new-build retirements and legacy retirements all happen at the
    % year-end hour t = 8760*y, so the new level holds for the following year.
    % With retireOn = false and a constant legacy schedule this equals version 2.
    for i = 1:n_sources
        Lh = lifeTime(i) * yearLen;            % lifetime in hours
        % t = 1
        row = row + 1;
        addCoef(row, idxK(i,1), 1);
        addCoef(row, idxZ(i,1), -p(i));
        rhs(row,1)   = legacyYear(i,1);
        sense(row,1) = '=';

        % t >= 2
        for t = 2:T
            row = row + 1;
            addCoef(row, idxK(i,t),   1);
            addCoef(row, idxK(i,t-1), -1);
            addCoef(row, idxZ(i,t),   -p(i));
            dLeg = 0;
            if mod(t, yearLen) == 0
                yE = t / yearLen;
                if yE < nYears
                    dLeg = legacyYear(i, yE+1) - legacyYear(i, yE);   % legacy retirement (<= 0)
                end
                if retireOn && t - Lh >= 1
                    addCoef(row, idxZ(i, t - Lh), p(i));             % vintage built L years ago retires
                end
            end
            rhs(row,1)   = dLeg;
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
    % K changes only at year-end hours, so one row per capacity level is enough:
    % t = 1 (first-year level) and t = 8760*y (level held during year y+1).
    tLand    = [1, yearLen:yearLen:T];
    landRows = zeros(numel(tLand), 1);
    for kL = 1:numel(tLand)
        row = row + 1;
        addCoef(row, idxK(2,tLand(kL)), areaPerSolar);
        rhs(row,1)   = maxAreaSolar;
        sense(row,1) = '<';
        landRows(kL) = row;
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
        
        % 1. CAPEX on NEW builds Z: annuity paid from the build year for lifeTime
        %    years (retireOn) or to the end of the horizon (version 2)
        if mod(t, 8760) == 0
            for i = 1:n_sources
                if retireOn
                    yLast = min(nYears, idxy + lifeTime(i) - 1);
                else
                    yLast = nYears;
                end
                pv_multiplier = sum(df_yearly(idxy:yLast));
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

    % (C8) Build-rate limit on NEW builds: p*Z(i,t) <= min(maxRamp(i), rampYear(i,y)), t = 8760*y
    % Applied to builds (not to the net change in K) so that replacing retired
    % capacity also counts against the limit. Without retirement this equals version 2.
    % rampYear holds the time-varying build-rate schedule (NaN = no schedule for that source)
    for i = 1:n_sources
        for y = 1:nYears-1
            t   = y * yearLen;
            lim = maxRamp(i);
            if ~isempty(P.rampYear)
                ry = P.rampYear(i, y);
                if ~isnan(ry), lim = min(lim, ry); end
            end
            row = row + 1;
            addCoef(row, idxZ(i,t), p(i));
            rhs(row,1)   = lim;
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

        % (C14) Minimum renewable share in 2050 (hard constraint, set in BASIC CONFIG):
    % sum_t [U_gas(t) + U_coal(t)] <= (1 - RE_TARGET_2050) * sum_t Demand(t),  t in 2050
    if P.RE_TARGET_2050 > 0
        y2050  = 2050 - startYr + 1;
        rng50  = (y2050-1)*yearLen + (1:yearLen);
        row    = row + 1;
        for t = rng50
            addCoef(row, idxU(3,t), 1);
            addCoef(row, idxU(4,t), 1);
        end
        rhs(row,1)   = (1 - P.RE_TARGET_2050) * sum(Demand(rng50));
        sense(row,1) = '<';
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

    % ---------- Build-only mode (used by run_model_tests.m) ----------
    if isfield(P, 'BUILD_ONLY') && P.BUILD_ONLY
        RES = struct();
        RES.model    = model;
        RES.landRows = landRows;
        RES.tLand    = tLand;
        RES.numVars  = numVars;
        return;
    end

    % ---------- Gurobi params ----------
    params = struct();
    params.Method         = 2;    % barrier
    params.Crossover      = -1;   % auto: convert barrier result to a clean vertex solution
    params.NumericFocus   = 1;    % more careful numerics
    params.BarHomogeneous = 1;    % robust near infeasibility (low budgets)
    params.Presolve       = 2;
    params.ScaleFlag      = 1;

    params.TimeLimit     = 14400; % 4 hours (edit as needed)

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

        RES.Dual_Land_year             = NaN(numel(landRows),1);
        RES.Dual_Land_Sum              = NaN;
        RES.Dual_Budget                = NaN;
        RES.LandFullYear               = NaN;

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

    % ---------- Shadow prices ----------
    % Units: objective units per unit of constraint.
    %   OBJECTIVE = 'emissions': land -> tCO2e per km^2 ; budget -> tCO2e per million NIS
    %   OBJECTIVE = 'cost'     : land -> million NIS per km^2 (budget not active)
    % Gurobi sign (minimisation): a binding '<' constraint has pi <= 0
    % (relaxing it lowers the objective). Values are reported as positive magnitudes.
    Dual_Land_year = NaN(numel(landRows),1);
    Dual_Budget    = NaN;
    if isfield(result,'pi') && ~isempty(result.pi)
        Dual_Land_year = -result.pi(landRows);
    end
    if isfield(result,'rc') && ~isempty(result.rc) && isfinite(ub(idxC(T)))
        % rc of C(T) at its upper bound = d(objective)/d(budget) = d(emissions)/d(budget) + epsCost.
        % Reported: emissions avoided per extra million NIS (0 if the budget does not bind).
        if result.x(idxC(T)) >= ub(idxC(T)) - 1e-6 * max(1, ub(idxC(T)))
            Dual_Budget = -result.rc(idxC(T)) + epsCost;
        else
            Dual_Budget = 0;
        end
    end
    % first year in which the land cap is full (level held during that year)
    landLevel   = areaPerSolar * result.x(idxK(2, tLand));   % per row in tLand
    fullIdx     = find(landLevel >= maxAreaSolar - 1e-3, 1, 'first');
    LandFullYear = NaN;
    if ~isempty(fullIdx)
        LandFullYear = min(startYr + fullIdx - 1, startYr + nYears - 1);   % row k = level held in year startYr+k-1
    end

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
            if retireOn
                alive = (Y - y_build) <= (lifeTime(:) - 1);   % annuity paid only over the lifetime
            else
                alive = true(n_sources,1);
            end
            capex_payment = capex_payment + alive .* mw_built .* (cap(y_build, :)' .* CRF');
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
    totalEmis_t  = result.objval - epsCost * result.x(idxC(T));   % remove the tie-breaking term
    totalEmis_Mt = totalEmis_t / 1e6;

    endYr = startYr + nYears - 1;

    fprintf('\n=== SUMMARY (scenario) ===\n');
    fprintf('Horizon years           : %d to %d (%d years)\n', startYr, endYr, nYears);
    if strcmp(P.OBJECTIVE, 'cost')
        fprintf('Objective (min cost)    : %.4g billion NIS (emissions reported in the KPI table)\n', result.objval / 1e3);
    else
        fprintf('Minimum total emissions : %.3f MtCO2e (%.0f tCO2e)\n', totalEmis_Mt, totalEmis_t);
    end
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
                if retireOn && (y - y_build) > (lifeTime(i) - 1)
                    continue;   % annuity already fully paid
                end
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
    RES.totalEmissions        = TotalEmissions_AllYears;   % tCO2e (from emitYear; valid for both objectives)

    RES.genYear  = genYear;
    RES.capYear  = capYear;
    RES.emitYear = emitYear;
    RES.demYear  = demYear;
    RES.areaYear = areaYear;

    RES.opCostYearBySource    = opCostYearBySource;
    RES.extCostYearBySource   = extCostYearBySource;
    RES.buildCostYearBySource = buildCostYearBySource;
    RES.ExternalitiesYear     = ExternalitiesYear;
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

    RES.Dual_Land_year = Dual_Land_year;        % row k = capacity level held in year startYr+k-1 (last row = end of 2050)
    RES.Dual_Land_Sum  = sum(Dual_Land_year, 'omitnan');
    RES.Dual_Budget    = Dual_Budget;
    RES.LandFullYear   = LandFullYear;

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
