function RESERVE_BETA_ANALYSIS()
% RESERVE_BETA_ANALYSIS  Figures for the reserve-margin chapter: the hard
% firm-capacity constraint (C13) and the battery capacity credit beta.
% Tabbed window, same style as COMPARE_NUCLEAR (white background).
%
%   Tab 1 - The hard constraint: gas capacity vs. max hourly gas dispatch vs.
%           capacity required by C13, and gas capacity factor (beta = 0, 420)
%   Tab 2 - Economic minimum vs. beta: total cost, cumulative emissions,
%           gas and battery capacity in 2050 (cost-min runs)
%   Tab 3 - Cost waterfall: economic minimum beta = 0 -> WF_BETA (FOCUS_AREA)
%   Tab 4 - Build-out over time, emission-min runs at 420 (rows = land cap)
%   Tab 5 - Build-out over time, cost-min runs
%   Tab 6 - Heatmap land x beta: change in cumulative emissions vs. beta = 0 (420)
%   Tab 7 - (optional) Mesh land x beta: cumulative emissions (420)
%   Tab 8 - FOCUS_AREA at 420: annual emissions, 2050 capacities,
%           cumulative emissions and renewable share by beta
%   Tab 9 - Validity of beta: deliverable fraction of battery power at the
%           critical hours of C13, compared with the credited beta
%
%   The user selects four KPI_summary files (.mat or .csv):
%     1) main grid, emission-min, beta = 0      (e.g. KPI_noNuc_final)
%     2) beta sweep, emission-min, budget 420
%     3) economic minimum (cost-min), beta = 0
%     4) beta sweep, cost-min
%   Scenario results are read from <run folder>\scenarios\<scenario>\results_heavy.mat
%   Runs whose results are identical (e.g. beta = 0.3, 0.5, 0.7 at 420) are
%   drawn once and labelled together.

    % ---------------- settings ----------------
    AREAS      = [400 600 850];          % km2
    BETAS      = [0 0.1 0.3 0.5 0.7];
    BUDGET     = 420e9;                  % NIS (emission-min runs)
    FOCUS_AREA = 850;                    % km2 (tabs 3 and 8)
    WF_BETA    = 0.5;                    % waterfall: beta = 0 -> WF_BETA
    SHOW_MESH  = true;                   % tab 7
    RM         = 1.20;                   % reserve margin used in C13
    FS         = 26;                     % base font size

    % ---------------- load the four KPI files ----------------
    [K1, r1] = find_run_kpi('Objective','emissions', 'Nuclear',false, 'BetaSweep',false, ...
    'Prompt','1/4: MAIN GRID (emission-min, beta = 0)', 'AlwaysAsk',true);
    [K2, r2] = find_run_kpi('Objective','emissions', 'Nuclear',false, 'BetaSweep',true, ...
        'Prompt','2/4: BETA SWEEP, emission-min (420)', 'AlwaysAsk',true);
    [K3, r3] = find_run_kpi('Objective','cost', 'Nuclear',false, 'BetaSweep',false, ...
        'Prompt','3/4: ECONOMIC MINIMUM (cost-min, beta = 0)', 'AlwaysAsk',true);
    [K4, r4] = find_run_kpi('Objective','cost', 'Nuclear',false, 'BetaSweep',true, ...
        'Prompt','4/4: BETA SWEEP, cost-min', 'AlwaysAsk',true);
    E0 = local_std(K1, r1);  E0 = E0(abs(E0.MaxCost - BUDGET) < 1e6 & ismember(E0.MaxAreaSolar, AREAS), :);
    E0.Beta(:) = 0;
    EB = local_std(K2, r2);  EB = EB(abs(EB.MaxCost - BUDGET) < 1e6 & ismember(EB.MaxAreaSolar, AREAS), :);
    EM = sortrows([E0; EB], {'MaxAreaSolar', 'Beta'});      % emission-min, 420

    C0 = local_std(K3, r3);  C0 = C0(ismember(C0.MaxAreaSolar, AREAS), :);
    C0.Beta(:) = 0;
    CB = local_std(K4, r4);  CB = CB(ismember(CB.MaxAreaSolar, AREAS), :);
    CM = sortrows([C0; CB], {'MaxAreaSolar', 'Beta'});      % cost-min

    [keepE, labE] = local_dedupe(EM);
    [keepC, labC] = local_dedupe(CM);

    % ---------------- window ----------------
    fig = uifigure('Name', 'Reserve margin and battery capacity credit (beta)', ...
                   'Position', [60 40 1280 760], 'Color', 'white');
    tg  = uitabgroup(fig, 'Position', [10 10 1260 740]);

    % ---------------- pre-load the scenario results that are drawn ----------------
    cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    jobs = {};
    for i = find(keepE)', jobs{end+1} = {EM, i}; end %#ok<AGROW>
    for i = find(keepC)', jobs{end+1} = {CM, i}; end %#ok<AGROW>
    iw = local_pick(CM, FOCUS_AREA, WF_BETA);
    if ~isempty(iw), jobs{end+1} = {CM, iw}; end
    dlg = uiprogressdlg(fig, 'Title', 'Loading scenario results', 'Value', 0);
    for k = 1:numel(jobs)
        T = jobs{k}{1};  i = jobs{k}{2};
        dlg.Message = sprintf('%s  (%d/%d)', T.Scenario(i), k, numel(jobs));
        dlg.Value   = (k - 1) / numel(jobs);
        local_getS(T, i, cache, RM);
    end
    close(dlg);

    % =====================================================================
    % TAB 1 - the hard constraint (beta = 0, 420)
    % =====================================================================
    tab = uitab(tg, 'Title', 'Hard constraint (β = 0)', 'BackgroundColor', 'white');
    [ax, pos] = local_axGrid(tab, 2, numel(AREAS), FS);
    for c = 1:numel(AREAS)
        a = AREAS(c);  i = local_pick(EM, a, 0);
        if isempty(i), local_msg(ax(1,c), 'missing'); local_msg(ax(2,c), 'missing'); continue; end
        S = local_getS(EM, i, cache, RM);
        h1 = plot(ax(1,c), S.years, S.cap(3,:) / 1e3, '-',  'Color', [0.85 0.33 0.10], 'LineWidth', 2.5);
        h2 = plot(ax(1,c), S.years, S.gasReq / 1e3,   ':',  'Color', [0 0 0],          'LineWidth', 2);
        i3 = local_pick(EM, a, 0.3);
        if isempty(i3), warning('No beta = 0.3 run for %d km2', a); continue; end
        S3 = local_getS(EM, i3, cache, RM);
        h3 = plot(ax(1,c), S3.years, S3.cap(3,:) / 1e3, '--', 'Color', [0.00 0.45 0.74], 'LineWidth', 2);
        title(ax(1,c), sprintf('%d km^2 – gas capacity [GW]', a), 'FontWeight', 'bold', 'Color', 'black');
        if c == 1
            lg = legend(ax(1,c), [h1 h2 h3], {'Installed (β = 0)', 'Required by C13', 'Installed at β = 0.3'}, ...
                'Location', 'northwest');
            local_legendStyle(lg, FS - 8);
            ylabel(ax(1,c), '[GW]', 'FontWeight', 'bold', 'Color', 'black');
        end
        plot(ax(2,c), S.years, 100 * S.gasCF, '-o', 'Color', [0.85 0.33 0.10], 'LineWidth', 1.5, ...
            'MarkerSize', 4, 'MarkerFaceColor', [0.85 0.33 0.10]);
        title(ax(2,c), sprintf('%d km^2 – gas capacity factor [%%]', a), 'FontWeight', 'bold', 'Color', 'black');
        xlabel(ax(2,c), 'Year', 'FontWeight', 'bold', 'Color', 'black'); 
        if c == 1, ylabel(ax(2,c), '[%]', 'FontWeight', 'bold', 'Color', 'black'); end
        ylim(ax(2,c), [0 max(5, ceil(max(100 * S.gasCF) / 10) * 10)]);
    end
    local_reapply(ax, pos);

    fprintf('\n=== Tab 1: gas in 2050, emission-min, beta = 0, budget %.0f x10^9 ===\n', BUDGET/1e9);
    fprintf('%6s | %10s %10s %10s %8s\n', 'Land', 'Cap[GW]', 'Req[GW]', 'Cap_b03', 'CF[%]');
    for a = AREAS
        i = local_pick(EM, a, 0);  if isempty(i), continue; end
        S = local_getS(EM, i, cache, RM);
        i3 = local_pick(EM, a, 0.3);  S3 = local_getS(EM, i3, cache, RM);
        fprintf('%6d | %10.1f %10.1f %10.1f %8.1f\n', a, S.cap(3,end)/1e3, S.gasReq(end)/1e3, ...
            S3.cap(3,end)/1e3, 100*S.gasCF(end));
    end

    % =====================================================================
    % TAB 2 - economic minimum vs beta
    % =====================================================================
    tab = uitab(tg, 'Title', 'Economic minimum vs β', 'BackgroundColor', 'white');
    [ax, pos] = local_axGrid(tab, 1, 3, FS);
    hA = gobjects(0);  labA = {};
    for a = AREAS
        rows = find(CM.MaxAreaSolar == a);
        if isempty(rows), continue; end
        b    = CM.Beta(rows);
        hasB = any(b == 0);
        col  = local_areaColor(a);
        if hasB, ls = '-'; mf = col; else, ls = '--'; mf = 'white'; end
        cost = CM.Cost(rows) / 1e9;  em = CM.Em(rows) / 1e6;
        h = plot(ax(1), b, cost, [ls 'o'], 'Color', col, 'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', mf);
        plot(ax(2), b, em, [ls 'o'], 'Color', col, 'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', mf);
        plot(ax(3), b, CM.Gas(rows) / 1e3,  [ls 'o'], 'Color', col, 'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', mf);
        plot(ax(3), b, CM.Batt(rows) / 1e3, [':' 's'], 'Color', col, 'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', mf);
        hA(end+1) = h; %#ok<AGROW>
        if hasB
            labA{end+1} = sprintf('%d km^2', a); %#ok<AGROW>
            c0 = cost(b == 0);  e0 = em(b == 0);
            for k = find(b > 0)'
                text(ax(1), b(k), cost(k), sprintf('  %+.1f%%', 100*(cost(k)/c0 - 1)), 'Color', col, ...
                    'FontSize', FS - 5, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom');
                text(ax(2), b(k), em(k), sprintf('  %+.0f%%', 100*(em(k)/e0 - 1)), 'Color', col, ...
                    'FontSize', FS - 5, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom');
            end
        else
            labA{end+1} = sprintf('%d km^2 (no β = 0 run)', a); %#ok<AGROW>
        end
    end
    title(ax(1), '(a) Minimum total cost (NPV)', 'FontWeight', 'bold', 'Color', 'black');
    ylabel(ax(1), 'Total discounted cost [₪×10^9]', 'FontWeight', 'bold', 'Color', 'black');
    title(ax(2), '(b) Cumulative emissions 2023–2050', 'FontWeight', 'bold', 'Color', 'black');
    ylabel(ax(2), 'Cumulative emissions [MtCO_2e]', 'FontWeight', 'bold', 'Color', 'black');
    title(ax(3), '(c) Capacity in 2050: gas (solid) / battery (dotted)', 'FontWeight', 'bold', 'Color', 'black');
    ylabel(ax(3), 'Capacity [GW]', 'FontWeight', 'bold', 'Color', 'black');
    for p = 1:3
        xlabel(ax(p), 'Battery capacity credit β', 'FontWeight', 'bold', 'Color', 'black');
        xticks(ax(p), BETAS);  xlim(ax(p), [-0.05 0.75]);
    end
    if ~isempty(hA)
        lg = legend(ax(1), hA, labA, 'Location', 'southwest');  local_legendStyle(lg, FS - 3);
    end
    local_reapply(ax, pos);
    local_printTable(CM, 'Tab 2: cost-min runs');

    % =====================================================================
    % TAB 3 - cost waterfall, beta = 0 -> WF_BETA
    % =====================================================================
    tab = uitab(tg, 'Title', sprintf('Cost waterfall β = 0 → %.1f', WF_BETA), 'BackgroundColor', 'white');
    [ax, pos] = local_axGrid(tab, 1, 1, FS);
    i0 = local_pick(CM, FOCUS_AREA, 0);  i1 = local_pick(CM, FOCUS_AREA, WF_BETA);
    if isempty(i0) || isempty(i1)
        local_msg(ax, 'Missing cost-min run for the waterfall');
    else
        S0 = local_getS(CM, i0, cache, RM);  S1 = local_getS(CM, i1, cache, RM);
        local_waterfall(ax, S0, S1, CM.Cost(i0), CM.Cost(i1), FOCUS_AREA, WF_BETA, FS);
    end
    local_reapply(ax, pos);

    % =====================================================================
    % TABS 4-5 - build-out over time
    % =====================================================================
    tab = uitab(tg, 'Title', 'Build-out: emission-min (420)', 'BackgroundColor', 'white');
    local_buildTab(tab, EM, keepE, labE, AREAS, cache, RM, FS, ...
        sprintf('emission-min, budget ₪%.0f×10^9', BUDGET/1e9));
    tab = uitab(tg, 'Title', 'Build-out: cost-min', 'BackgroundColor', 'white');
    local_buildTab(tab, CM, keepC, labC, AREAS, cache, RM, FS, 'cost-min');

    % =====================================================================
    % TAB 6 - heatmap land x beta (420)
    % =====================================================================
    nA = numel(AREAS);  nB = numel(BETAS);
    EmAbs = nan(nA, nB);
    for r = 1:nA
        for c = 1:nB
            i = local_pick(EM, AREAS(r), BETAS(c));
            if ~isempty(i), EmAbs(r,c) = EM.Em(i) / 1e6; end
        end
    end
    D = EmAbs - EmAbs(:,1);                 % change vs beta = 0 [Mt] (negative = saving)
    tab = uitab(tg, 'Title', 'Heatmap: land × β (420)', 'BackgroundColor', 'white');
    [ax, pos] = local_axGrid(tab, 1, 1, FS);
    local_betaHeatmap(ax, D, EmAbs, AREAS, BETAS, BUDGET, FS);
    local_reapply(ax, pos);

    % =====================================================================
    % TAB 7 - mesh land x beta (420)
    % =====================================================================
    if SHOW_MESH
        tab = uitab(tg, 'Title', 'Mesh: land × β (420)', 'BackgroundColor', 'white');
        ax = uiaxes(tab, 'Position', [50 50 1150 620], 'Color', 'white');
        local_axStyle(ax, FS);  hold(ax, 'on');
        surf(ax, BETAS, AREAS, EmAbs, 'FaceColor', [0.47 0.67 0.19], 'FaceAlpha', 0.45, ...
            'EdgeColor', [0.20 0.40 0.05], 'LineWidth', 1);
        [Bm, Am] = meshgrid(BETAS, AREAS);
        plot3(ax, Bm(:), Am(:), EmAbs(:), 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5);
        view(ax, -40, 25);  ax.ZColor = 'black';
        xlabel(ax, 'Battery capacity credit β', 'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black');
        ylabel(ax, 'Solar land cap [km^2]',      'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black');
        zlabel(ax, 'Cumulative emissions 2023–2050 [MtCO_2e]', 'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black');
        title(ax, sprintf('Cumulative emissions by land cap and β – budget ₪%.0f×10^9', BUDGET/1e9), ...
            'FontWeight', 'bold', 'FontSize', FS + 2, 'Color', 'black');
        xticks(ax, BETAS);  yticks(ax, AREAS);
    end

    % =====================================================================
    % TAB 8 - focus scenario (FOCUS_AREA, 420) by beta
    % =====================================================================
    tab = uitab(tg, 'Title', sprintf('%d km² at 420: by β', FOCUS_AREA), 'BackgroundColor', 'white');
    [ax, pos] = local_axGrid(tab, 2, 2, FS);
    rowsF = find(EM.MaxAreaSolar == FOCUS_AREA);
    if isempty(rowsF)
        local_msg(ax(1,1), 'No runs for the focus area');
    else
        % (a) annual emissions, one line per distinct result
        h = gobjects(0);  lab = {};
        for i = rowsF(keepE(rowsF))'
            S = local_getS(EM, i, cache, RM);
            h(end+1) = plot(ax(1,1), S.years, S.emi / 1e6, '-', 'Color', local_betaColor(EM.Beta(i)), 'LineWidth', 2); %#ok<AGROW>
            lab{end+1} = char(labE(i)); %#ok<AGROW>
        end
        lg = legend(ax(1,1), h, lab, 'Location', 'northeast');  local_legendStyle(lg, FS - 3);
        title(ax(1,1), '(a) Annual life-cycle emissions', 'FontWeight', 'bold', 'Color', 'black');
        ylabel(ax(1,1), '[MtCO_2e/yr]', 'FontWeight', 'bold', 'Color', 'black');
        xlabel(ax(1,1), 'Year', 'FontWeight', 'bold', 'Color', 'black');

        bl  = EM.Beta(rowsF);  xl = compose('β = %.1f', bl);
        % (b) capacities in 2050
        Y = [EM.Gas(rowsF) EM.Batt(rowsF) EM.Solar(rowsF)] / 1e3;
        hb = bar(ax(1,2), 1:numel(rowsF), Y, 'grouped');
        hb(1).FaceColor = [0.85 0.33 0.10];  hb(2).FaceColor = [0.47 0.67 0.19];  hb(3).FaceColor = [0.93 0.69 0.13];
        ylim(ax(1,2), [0 1.35 * max(Y(:))]);
        lg = legend(ax(1,2), {'Gas', 'Battery', 'Solar PV'}, 'Location', 'north', 'Orientation', 'horizontal');
        local_legendStyle(lg, FS - 8);
        title(ax(1,2), '(b) Installed capacity in 2050', 'FontWeight', 'bold', 'Color', 'black');
        ylabel(ax(1,2), '[GW]', 'FontWeight', 'bold', 'Color', 'black');
        % (c) cumulative emissions
        em = EM.Em(rowsF) / 1e6;
        local_barLabels(ax(2,1), em, bl, '%.0f', FS);
        title(ax(2,1), '(c) Cumulative emissions 2023–2050', 'FontWeight', 'bold', 'Color', 'black');
        ylabel(ax(2,1), '[MtCO_2e]', 'FontWeight', 'bold', 'Color', 'black');
        % (d) renewable share
        re = EM.RE(rowsF);
        local_barLabels(ax(2,2), re, bl, '%.1f', FS);
        ylim(ax(2,2), [floor(min(re)) - 2, ceil(max(re)) + 1]);
        title(ax(2,2), '(d) Renewable share in 2050 (axis not from zero)', 'FontWeight', 'bold', 'Color', 'black');
        ylabel(ax(2,2), '[%]', 'FontWeight', 'bold', 'Color', 'black');
        for p = [3 2 4]                                  % (b), (c), (d) share the x labels
            xticks(ax(p), 1:numel(rowsF));  xticklabels(ax(p), xl);
        end
    end
    local_reapply(ax, pos);
    local_printTable(EM, sprintf('Tab 8: emission-min runs, budget %.0f x10^9', BUDGET/1e9));

    % =====================================================================
    % TAB 9 - validity of beta
    % =====================================================================
    tab = uitab(tg, 'Title', 'Validity of β', 'BackgroundColor', 'white');
    [ax, pos] = local_axGrid(tab, 2, nA, FS);
    sets = {EM, keepE, labE, 'emission-min (420)'; CM, keepC, labC, 'cost-min'};
    fprintf('\n=== Tab 9: deliverable fraction of battery power at critical hours (worst hour, 2030-2050) ===\n');
    for s = 1:2
        T = sets{s,1};  keep = sets{s,2};  labs = sets{s,3};
        for c = 1:nA
            a = AREAS(c);  axc = ax(s,c);  h = gobjects(0);  lab = {};
            for i = find(T.MaxAreaSolar == a & keep)'
                S   = local_getS(T, i, cache, RM);
                col = local_betaColor(T.Beta(i));
                h(end+1) = plot(axc, S.years, S.phiMin, '-o', 'Color', col, 'LineWidth', 1.8, ...
                    'MarkerSize', 4, 'MarkerFaceColor', col); %#ok<AGROW>
                lab{end+1} = char(labs(i)); %#ok<AGROW>
                if T.Beta(i) > 0
                    plot(axc, [S.years(1) S.years(end)], [1 1] * T.Beta(i), '--', 'Color', col, 'LineWidth', 1.2);
                end
                m = S.years >= 2030;
                fprintf('%-18s %4d km2  beta %.1f : min %.2f  mean %.2f\n', sets{s,4}, a, T.Beta(i), ...
                    min(S.phiMin(m)), mean(S.phiMean(m)));
            end
            ylim(axc, [0 1.05]);
            title(axc, sprintf('%s – %d km^2', sets{s,4}, a), 'FontWeight', 'bold', 'Color', 'black');
            if c == 1
                ylabel(axc, 'Deliverable share of battery power', 'FontWeight', 'bold', 'Color', 'black');
            end
            if s == 2, xlabel(axc, 'Year', 'FontWeight', 'bold', 'Color', 'black'); end
            if ~isempty(h)
                lg = legend(axc, h, lab, 'Location', 'southeast');  local_legendStyle(lg, FS - 5);
            else
                local_msg(axc, 'no runs');
            end
        end
    end
    local_reapply(ax, pos);
    fprintf(['(solid = lowest deliverable share over the critical hours of each year: min(K_batt, eta_dis*E(t-1)) / K_batt;\n', ...
             ' dashed = credited beta. Solid above dashed = the credit is conservative in the modelled weather year)\n\n']);
end

% =========================================================================
%  DATA HELPERS
% =========================================================================
function [K, scenRoot] = local_loadKPI(promptStr)
    [f, p] = uigetfile({'*.mat;*.csv', 'KPI summary (*.mat, *.csv)'}, promptStr);
    if isequal(f, 0), error('No file selected.'); end
    file = fullfile(p, f);
    [~, ~, ext] = fileparts(file);
    if strcmpi(ext, '.mat')
        S = load(file, 'KPI');  K = S.KPI;
    else
        K = readtable(file);
    end
    K = K(string(K.ResultStatus) == "OPTIMAL", :);
    runDir   = fileparts(fileparts(file));                 % <run>\tables\KPI_summary.* -> <run>
    scenRoot = fullfile(runDir, 'scenarios');
    if ~isfolder(scenRoot)
        scenRoot = uigetdir(runDir, ['Select the "scenarios" folder for: ' promptStr]);
        if isequal(scenRoot, 0), error('No scenarios folder selected.'); end
    end
    fprintf('%s\n  KPI: %s  (%d OPTIMAL)\n  scenarios: %s\n', promptStr, file, height(K), scenRoot);
end

function T = local_std(K, root)
% Common columns for all four KPI files (BetaX is missing in the older runs).
    n = height(K);
    if ismember('BetaX', K.Properties.VariableNames), b = K.BetaX(:); else, b = zeros(n, 1); end
    T = table(string(K.Scenario(:)), K.MaxCost(:), K.MaxAreaSolar(:), b, ...
        K.TotalCost_AllYears(:), K.TotalEmissions_AllYears(:), K.RenewablesPct2050(:), ...
        K.Cap2050_Gas(:), K.Cap2050_Battery(:), K.Cap2050_Solar(:), K.SolarLand_km2(:), ...
        repmat(string(root), n, 1), ...
        'VariableNames', {'Scenario', 'MaxCost', 'MaxAreaSolar', 'Beta', 'Cost', 'Em', 'RE', ...
                          'Gas', 'Batt', 'Solar', 'Land', 'Root'});
end

function i = local_pick(T, area, beta)
    i = find(T.MaxAreaSolar == area & abs(T.Beta - beta) < 1e-9, 1);
end

function [keep, lab] = local_dedupe(T)
% Runs of the same land cap with identical results are drawn once:
% "beta = 0.3 (= 0.5, 0.7)".
    keep = true(height(T), 1);  lab = strings(height(T), 1);
    for a = unique(T.MaxAreaSolar)'
        idx = find(T.MaxAreaSolar == a);
        [~, o] = sort(T.Beta(idx));  idx = idx(o);
        for k = 1:numel(idx)
            i = idx(k);
            if ~keep(i), continue; end
            same = [];
            for m = k+1:numel(idx)
                j = idx(m);
                if keep(j) && abs(T.Em(j) - T.Em(i)) <= 1e-6 * T.Em(i) && ...
                        abs(T.Cost(j) - T.Cost(i)) <= 1e-6 * T.Cost(i) && abs(T.Gas(j) - T.Gas(i)) < 1
                    keep(j) = false;  same(end+1) = T.Beta(j); %#ok<AGROW>
                end
            end
            lab(i) = sprintf('\\beta = %.1f', T.Beta(i));
            if ~isempty(same)
                lab(i) = lab(i) + " (= " + strjoin(compose('%.1f', same), ', ') + ")";
            end
        end
    end
end

function S = local_getS(T, i, cache, RM)
% Small summary of one scenario; results_heavy.mat is loaded once and released.
    f = char(fullfile(T.Root(i), T.Scenario(i), 'results_heavy.mat'));
    if isKey(cache, f), S = cache(f); return; end
    if ~isfile(f), error('File not found: %s', f); end
    L = load(f, 'RES');  R = L.RES;  P = R.P;
    if ~isfield(P, 'Demand') || ~isfield(P, 'cf')
        error('RES.P has no Demand/cf: %s', f);
    end
    beta = T.Beta(i);
    yl  = P.yearLen;  nY = size(R.genYear, 2);
    U   = R.U;  K = R.K;  E = R.E(:)';  D = P.Demand(:);  cf = P.cf(:);
    eta = P.eta_dis;  E0 = P.E0;

    S.years = R.BaseYear + (0:nY-1);
    S.cap   = R.capYear;             % MW, capacity during the year
    S.gen   = R.genYear;             % MWh
    S.emi   = R.emitYear(:)';        % tCO2e
    S.capexSrc = sum(R.buildCostYearBySource, 2);   % NIS, PV
    S.opexSrc  = sum(R.opCostYearBySource, 2);
    S.extSrc   = sum(R.extCostYearBySource, 2);

    S.gasMax  = zeros(1, nY);  S.gasCF   = zeros(1, nY);  S.gasReq = zeros(1, nY);
    S.phiMin  = nan(1, nY);    S.phiMean = nan(1, nY);
    for y = 1:nY
        rng = (y-1)*yl + (1:yl);
        S.gasMax(y) = max(U(3, rng));
        S.gasCF(y)  = S.gen(3, y) / max(1, S.cap(3, y) * yl);

        % critical hours, exactly as in C13 of OPT_ONE_SENS
        yd = D(rng);  ycf = cf(rng);
        [~, ia] = sort(yd, 'descend');
        pa = rng(ia(1:10));
        z  = find(ycf == 0);
        [~, ib] = sort(yd(z), 'descend');
        pb = rng(z(ib(1:min(10, numel(ib)))));
        crit = unique([pa(:); pb(:)])';

        % gas capacity required by C13 given the other terms of the solution
        req = RM * (D(crit)' - U(2, crit)) - K(1, crit) - K(4, crit) - beta * K(5, crit);
        S.gasReq(y) = max(req);

        % deliverable share of battery power at the critical hours
        Ep = zeros(size(crit));
        for k = 1:numel(crit)
            if crit(k) > 1, Ep(k) = E(crit(k) - 1); else, Ep(k) = E0; end
        end
        Kb  = K(5, crit);
        phi = min(Kb, eta * Ep) ./ max(Kb, eps);
        S.phiMin(y)  = min(phi);
        S.phiMean(y) = mean(phi);
    end
    cache(f) = S;
end

function local_printTable(T, ttl)
    fprintf('\n=== %s ===\n', ttl);
    fprintf('%6s %5s | %10s %10s %8s | %8s %8s %8s %7s\n', 'Land', 'beta', 'Cost[bn]', 'Em[Mt]', 'dEm[%]', ...
        'Gas[GW]', 'Batt[GW]', 'Land', 'RE[%]');
    for i = 1:height(T)
        i0 = local_pick(T, T.MaxAreaSolar(i), 0);
        if isempty(i0), d = NaN; else, d = 100 * (T.Em(i) / T.Em(i0) - 1); end
        fprintf('%6d %5.1f | %10.2f %10.1f %8.1f | %8.1f %8.1f %8.0f %7.1f\n', T.MaxAreaSolar(i), T.Beta(i), ...
            T.Cost(i)/1e9, T.Em(i)/1e6, d, T.Gas(i)/1e3, T.Batt(i)/1e3, T.Land(i), T.RE(i));
    end
end

% =========================================================================
%  PLOT HELPERS
% =========================================================================
function local_buildTab(tab, T, keep, labs, AREAS, cache, RM, FS, modeStr)
% rows = land caps, columns = gas / battery / solar capacity over time
    techs = [3 5 2];  tName = {'Gas', 'Battery', 'Solar PV'};
    [ax, pos] = local_axGrid(tab, numel(AREAS), 3, FS);
    for r = 1:numel(AREAS)
        a = AREAS(r);  rows = find(T.MaxAreaSolar == a & keep);
        h = gobjects(0);  lab = {};
        for c = 1:3
            for i = rows'
                S = local_getS(T, i, cache, RM);
                hh = plot(ax(r,c), S.years, S.cap(techs(c), :) / 1e3, '-', ...
                    'Color', local_betaColor(T.Beta(i)), 'LineWidth', 2);
                if c == 1, h(end+1) = hh; lab{end+1} = char(labs(i)); end %#ok<AGROW>
            end
            title(ax(r,c), sprintf('%d km^2 – %s [GW]', a, tName{c}), 'FontWeight', 'bold', 'Color', 'black');
            if r == numel(AREAS), xlabel(ax(r,c), 'Year', 'FontWeight', 'bold', 'Color', 'black'); end
            if isempty(rows), local_msg(ax(r,c), 'no runs'); end
        end
        if ~isempty(h)
            lg = legend(ax(r,1), h, lab, 'Location', 'northwest');  local_legendStyle(lg, FS - 10);
        end
    end
    local_reapply(ax, pos);
end

function local_waterfall(ax, S0, S1, cost0, cost1, area, beta, FS)
% Change in total discounted cost between two cost-min runs, by source and component.
    src  = {'Nuclear', 'Solar', 'Gas', 'Coal', 'Battery'};
    comp = {'CAPEX', 'OPEX', 'carbon'};
    M0 = [S0.capexSrc S0.opexSrc S0.extSrc] / 1e9;
    M1 = [S1.capexSrc S1.opexSrc S1.extSrc] / 1e9;
    dM = M1 - M0;
    names = {};  vals = [];  other = 0;
    for s = 1:5
        for c = 1:3
            if abs(dM(s,c)) >= 0.3
                names{end+1} = sprintf('%s %s', src{s}, comp{c}); %#ok<AGROW>
                vals(end+1)  = dM(s,c); %#ok<AGROW>
            else
                other = other + dM(s,c);
            end
        end
    end
    if abs(other) > 1e-6, names{end+1} = 'Other'; vals(end+1) = other; end
    t0 = sum(M0(:));  t1 = sum(M1(:));
    fprintf('\n=== Tab 3: waterfall check (bn NIS): KPI %.2f -> %.2f | by source %.2f -> %.2f ===\n', ...
        cost0/1e9, cost1/1e9, t0, t1);
    for k = 1:numel(vals), fprintf('  %-18s %+8.2f\n', names{k}, vals(k)); end

    n = numel(vals);  x = 1:(n + 2);  w = 0.35;
    cum = t0;  tops = t0;
    patch(ax, [1-w 1+w 1+w 1-w], [0 0 t0 t0], [0.55 0.55 0.55], 'EdgeColor', 'none');
    text(ax, 1, t0, sprintf('%.1f', t0), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'FontSize', FS - 3, 'FontWeight', 'bold', 'Color', 'black');
    for k = 1:n
        y0 = cum;  y1 = cum + vals(k);
        if vals(k) < 0, col = [0.30 0.65 0.30]; else, col = [0.80 0.25 0.20]; end
        patch(ax, x(k+1) + [-w w w -w], [y0 y0 y1 y1], col, 'EdgeColor', 'none');
        plot(ax, [x(k)+w x(k+1)-w], [y0 y0], ':', 'Color', [0.3 0.3 0.3]);
        text(ax, x(k+1), max(y0, y1), sprintf('%+.1f', vals(k)), 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'bottom', 'FontSize', FS - 4, 'FontWeight', 'bold', 'Color', 'black');
        cum = y1;  tops(end+1) = max(y0, y1); %#ok<AGROW>
    end
    plot(ax, [x(n+1)+w x(n+2)-w], [cum cum], ':', 'Color', [0.3 0.3 0.3]);
    patch(ax, x(end) + [-w w w -w], [0 0 t1 t1], [0.00 0.45 0.74], 'EdgeColor', 'none');
    text(ax, x(end), t1, sprintf('%.1f', t1), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'FontSize', FS - 3, 'FontWeight', 'bold', 'Color', 'black');

    lows = [t0 t1 t0 + cumsum(vals)];
    ylim(ax, [floor(min(lows) - 0.25 * (max(tops) - min(lows)) - 5), ceil(max(tops) + 5)]);
    xlim(ax, [0.4 x(end) + 0.6]);
    xticks(ax, x);
    xticklabels(ax, [{'β = 0'}, names, {sprintf('β = %.1f', beta)}]);
    ax.XTickLabelRotation = 30;
    ylabel(ax, 'Total discounted cost [₪×10^9] (axis not from zero)', 'FontWeight', 'bold', 'Color', 'black');
    title(ax, sprintf('Economic minimum at %d km^2: change in total cost from β = 0 to β = %.1f (green = saving)', ...
        area, beta), 'FontWeight', 'bold', 'Color', 'black');
end

function local_betaHeatmap(ax, D, EmAbs, AREAS, BETAS, BUDGET, FS)
    nA = numel(AREAS);  nB = numel(BETAS);
    V = -D;                                          % avoided emissions (positive)
    imagesc(ax, 1:nB, 1:nA, V, 'AlphaData', ~isnan(V));
    set(ax, 'YDir', 'normal');
    nC = 256;
    greens = [linspace(1.00, 0.00, nC)', linspace(1.00, 0.40, nC)', linspace(1.00, 0.10, nC)'];
    colormap(ax, greens);
    vmax = max(V(:), [], 'omitnan');  if ~(vmax > 0), vmax = 1; end
    caxis(ax, [0 vmax]);
    for r = 1:nA
        for c = 1:nB
            if isnan(EmAbs(r,c))
                txt = {'no run'};  col = [0.5 0.5 0.5];
            elseif c == 1
                txt = {sprintf('%.0f Mt', EmAbs(r,c)), '(baseline)'};  col = [0 0 0];
            else
                txt = {sprintf('%+.0f Mt', D(r,c)), sprintf('(%+.1f%%)', 100 * D(r,c) / EmAbs(r,1))};
                col = [1 1 1] * (V(r,c) / vmax > 0.55);
            end
            text(ax, c, r, txt, 'HorizontalAlignment', 'center', 'FontSize', FS - 2, ...
                'FontWeight', 'bold', 'Color', col);
        end
    end
    xticks(ax, 1:nB);  xticklabels(ax, compose('%.1f', BETAS));
    yticks(ax, 1:nA);  yticklabels(ax, compose('%d', AREAS));
    xlim(ax, [0.5 nB + 0.5]);  ylim(ax, [0.5 nA + 0.5]);
    grid(ax, 'off');
    xlabel(ax, 'Battery capacity credit β', 'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black');
    ylabel(ax, 'Solar land cap [km^2]',      'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black');
    title(ax, sprintf('Change in cumulative emissions 2023–2050 relative to β = 0 – budget ₪%.0f×10^9', BUDGET/1e9), ...
        'FontWeight', 'bold', 'FontSize', FS + 1, 'Color', 'black');
    cb = colorbar(ax);  cb.Color = 'black';  cb.FontSize = FS - 2;
    cb.Label.String = 'Avoided emissions [MtCO_2e]';  cb.Label.FontWeight = 'bold';
end

function local_barLabels(ax, v, bl, fmt, FS)
    hb = bar(ax, 1:numel(v), v, 0.6);
    hb.FaceColor = 'flat';
    for k = 1:numel(v), hb.CData(k,:) = local_betaColor(bl(k)); end
    for k = 1:numel(v)
        text(ax, k, v(k), sprintf(fmt, v(k)), 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'bottom', 'FontSize', FS - 4, 'FontWeight', 'bold', 'Color', 'black');
    end
end

function [ax, pos] = local_axGrid(parent, nr, nc, FS)
% Grid of uiaxes with identical plot boxes (inner positions).
    L0 = 120;  B0 = 100;  Wt = 1100;  Ht = 545;  gx = 120;  gy = 130;
    w = (Wt - (nc - 1) * gx) / nc;  h = (Ht - (nr - 1) * gy) / nr;
    ax = gobjects(nr, nc);  pos = cell(nr, nc);
    for r = 1:nr
        for c = 1:nc
            pos{r,c} = [L0 + (c-1)*(w + gx), B0 + (nr - r)*(h + gy), w, h];
            ax(r,c) = uiaxes(parent, 'Color', 'white');
            ax(r,c).PositionConstraint = 'innerposition';
            ax(r,c).InnerPosition = pos{r,c};
            local_axStyle(ax(r,c), FS - 2 * (nr > 1) - (nc > 2));
            hold(ax(r,c), 'on');
        end
    end
end

function local_reapply(ax, pos)
    for k = 1:numel(ax)
        if ~isvalid(ax(k)), continue; end
        xl = ax(k).XLim;
        if xl(1) >= 2000 && xl(2) <= 2100          % time axis: one tick per decade
            xticks(ax(k), 2020:10:2050);
        end
        ax(k).InnerPosition = pos{k};
    end
end

function local_axStyle(ax, FS)
    ax.Color     = 'white';
    ax.XColor    = 'black';  ax.YColor = 'black';
    ax.GridColor = [0.15 0.15 0.15];
    ax.FontSize  = FS - 2;
    ax.LineWidth = 1;
    ax.Box       = 'on';
    grid(ax, 'on');
end

function local_legendStyle(lg, fs)
    lg.Color     = 'white';
    lg.TextColor = 'black';
    lg.EdgeColor = [0.6 0.6 0.6];
    lg.FontSize  = fs;
end

function local_msg(ax, str)
    text(ax, 0.5, 0.5, str, 'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'Color', [0.5 0.5 0.5], 'FontWeight', 'bold');
end

function c = local_betaColor(b)
    pal = [0.00 0.00 0.00;     % beta = 0
           0.00 0.45 0.74;     % 0.1
           0.85 0.33 0.10;     % 0.3
           0.47 0.67 0.19;     % 0.5
           0.49 0.18 0.56];    % 0.7
    k = find(abs([0 0.1 0.3 0.5 0.7] - b) < 1e-9, 1);
    if isempty(k), c = [0.5 0.5 0.5]; else, c = pal(k,:); end
end

function c = local_areaColor(a)
    switch a
        case 400, c = [0.64 0.08 0.18];
        case 600, c = [0.93 0.69 0.13];
        case 850, c = [0.00 0.45 0.74];
        otherwise, c = [0.4 0.4 0.4];
    end
end
