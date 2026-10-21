function COMPARE_NUCLEAR()
% COMPARE_NUCLEAR  Comparison of the scenario grids WITH and WITHOUT nuclear
% in a tabbed window (same style as the other dashboards: white background).
%
%   Tab 1 - 3D mesh: renewable / low-carbon share 2050 vs budget and land
%   Tab 2 - 3D mesh: cumulative emissions 2023-2050 vs budget and land
%   Tab 3 - Representative scenarios: average system cost 2050
%           dashed = Direct LCOE (CAPEX + OPEX)
%           solid  = Social LCOE (direct + carbon cost 200 NIS/tCO2e, as in the model)
%   Tab 4 - Heatmap: cumulative emissions avoided by nuclear in every cell
%
%   The user selects KPI_summary (.mat or .csv) of each run.
%   Scenario results are read from <run folder>\scenarios\<scenario>\results_heavy.mat

    % ---------------- settings ----------------
    MESH_MIN_AREA      = 400;      % km2 - the 100 km2 benchmark is not drawn in the mesh
    REP_BUDGET         = 420e9;    % representative scenarios (same rule as the dashboard)
    REP_BUDGET_LOWLAND = 430e9;
    LOWLAND_MAX        = 100;      % km2
    C_NO  = [0.00 0.45 0.74];      % colour - without nuclear
    C_NUC = [0.85 0.33 0.10];      % colour - with nuclear
    FS    = 16;                    % base font size

    % ---------------- load both runs ----------------
    [K0, root0] = local_loadKPI('Select KPI_summary of the run WITHOUT nuclear');
    [K1, root1] = local_loadKPI('Select KPI_summary of the run WITH nuclear');

    % ---------------- window with tabs ----------------
    fig = uifigure('Name', 'Nuclear vs No-Nuclear Comparison', ...
                   'Position', [100 100 1280 750], 'Color', 'white');
    tg  = uitabgroup(fig, 'Position', [10 10 1260 730]);

    % =====================================================================
    % TAB 1 - mesh of renewable / low-carbon share
    % =====================================================================
    tab1 = uitab(tg, 'Title', 'Mesh: RE / Low-carbon share', 'BackgroundColor', 'white');
    ax1  = uiaxes(tab1, 'Position', [50 50 1180 620], 'Color', 'white');
    hold(ax1, 'on');
    [X, Y, Z0] = local_grid(K0, 'RenewablesPct2050', 1, MESH_MIN_AREA);
    [~, ~, Z1] = local_grid(K1, 'RenewablesPct2050', 1, MESH_MIN_AREA, X, Y);
    h0 = surf(ax1, X, Y, Z0, 'FaceColor', C_NO,  'FaceAlpha', 0.35, 'EdgeColor', C_NO,  'LineWidth', 1);
    h1 = surf(ax1, X, Y, Z1, 'FaceColor', C_NUC, 'FaceAlpha', 0.35, 'EdgeColor', C_NUC, 'LineWidth', 1);
    local_meshStyle(ax1, FS, 'Share of generation in 2050 [%]', ...
        'Renewable / low-carbon share in 2050 – with and without nuclear');
    lg = legend(ax1, [h0 h1], {'Without nuclear (renewable share)', ...
        'With nuclear (low-carbon share: renewables + nuclear)'}, 'Location', 'northeast');
    local_legendStyle(lg, FS);

    % =====================================================================
    % TAB 2 - mesh of cumulative emissions
    % =====================================================================
    tab2 = uitab(tg, 'Title', 'Mesh: Cumulative Emissions', 'BackgroundColor', 'white');
    ax2  = uiaxes(tab2, 'Position', [50 50 1180 620], 'Color', 'white');
    hold(ax2, 'on');
    [X, Y, Z0] = local_grid(K0, 'TotalEmissions_AllYears', 1e-6, MESH_MIN_AREA);
    [~, ~, Z1] = local_grid(K1, 'TotalEmissions_AllYears', 1e-6, MESH_MIN_AREA, X, Y);
    h0 = surf(ax2, X, Y, Z0, 'FaceColor', C_NO,  'FaceAlpha', 0.35, 'EdgeColor', C_NO,  'LineWidth', 1);
    h1 = surf(ax2, X, Y, Z1, 'FaceColor', C_NUC, 'FaceAlpha', 0.35, 'EdgeColor', C_NUC, 'LineWidth', 1);
    local_meshStyle(ax2, FS, 'Cumulative emissions 2023–2050 [MtCO_2e]', ...
        'Cumulative emissions 2023–2050 – with and without nuclear');
    lg = legend(ax2, [h0 h1], {'Without nuclear', 'With nuclear'}, 'Location', 'northeast');
    local_legendStyle(lg, FS);

    % =====================================================================
    % TAB 3 - representative scenarios: direct and social LCOE 2050
    % =====================================================================
    R0 = local_repCosts(K0, root0, REP_BUDGET, REP_BUDGET_LOWLAND, LOWLAND_MAX);
    R1 = local_repCosts(K1, root1, REP_BUDGET, REP_BUDGET_LOWLAND, LOWLAND_MAX);

    tab3 = uitab(tg, 'Title', 'LCOE 2050: Direct / Social', 'BackgroundColor', 'white');
    ax3  = uiaxes(tab3, 'Position', [50 50 1180 620], 'Color', 'white');
    hold(ax3, 'on');
    plot(ax3, R0.area, R0.direct, '--o', 'Color', C_NO,  'MarkerFaceColor', 'white', 'LineWidth', 1.5, 'MarkerSize', 8);
    plot(ax3, R1.area, R1.direct, '--s', 'Color', C_NUC, 'MarkerFaceColor', 'white', 'LineWidth', 1.5, 'MarkerSize', 8);
    plot(ax3, R0.area, R0.social, '-o',  'Color', C_NO,  'MarkerFaceColor', C_NO,    'LineWidth', 1.5, 'MarkerSize', 8);
    plot(ax3, R1.area, R1.social, '-s',  'Color', C_NUC, 'MarkerFaceColor', C_NUC,   'LineWidth', 1.5, 'MarkerSize', 8);
    local_costStyle(ax3, FS, 'Average system cost 2050 – direct and social, with and without nuclear');
    lg = legend(ax3, {'Without nuclear – Direct LCOE', 'With nuclear – Direct LCOE', ...
        'Without nuclear – Social LCOE', 'With nuclear – Social LCOE'}, 'Location', 'best');
    local_legendStyle(lg, FS);

    % =====================================================================
    % TAB 4 - heatmap: emissions avoided by nuclear (no-nuclear minus nuclear)
    % =====================================================================
    tab4 = uitab(tg, 'Title', 'Heatmap: Emissions Avoided by Nuclear', 'BackgroundColor', 'white');
    ax4  = uiaxes(tab4, 'Position', [50 50 1180 620], 'Color', 'white');
    local_diffHeatmap(ax4, K0, K1, FS);

    % ---------------- print the numbers (for the thesis text) ----------------
    fprintf('\n=== Representative scenarios: average system cost 2050 [NIS/kWh] ===\n');
    fprintf('%6s | %6s %8s %8s | %6s %8s %8s\n', 'Land', 'RE_no', 'Dir_no', 'Soc_no', 'LC_nuc', 'Dir_nuc', 'Soc_nuc');
    for k = 1:numel(R0.area)
        j = find(R1.area == R0.area(k), 1);
        if isempty(j), continue; end
        fprintf('%6d | %6.1f %8.4f %8.4f | %6.1f %8.4f %8.4f\n', R0.area(k), ...
            R0.re(k), R0.direct(k), R0.social(k), R1.re(j), R1.direct(j), R1.social(j));
    end
    fprintf('(RE_no = renewable share without nuclear; LC_nuc = low-carbon share with nuclear)\n\n');
end

% =========================================================================
%  HELPERS
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

    % <run>\tables\KPI_summary.* -> <run>\scenarios
    runDir   = fileparts(fileparts(file));
    scenRoot = fullfile(runDir, 'scenarios');
    if ~isfolder(scenRoot)
        scenRoot = uigetdir(runDir, ['Select the "scenarios" folder for: ' promptStr]);
    end
    fprintf('%s\n  KPI: %s  (%d OPTIMAL scenarios)\n  scenarios: %s\n', promptStr, file, height(K), scenRoot);
end

function [X, Y, Z] = local_grid(K, field, scale, minArea, X, Y)
% Regular grid budget (x, 1e11 NIS) x land (y, km2); missing scenarios = NaN.
    x = round(K.MaxCost(:) / 1e11, 2);
    y = K.MaxAreaSolar(:);
    z = K.(field)(:) * scale;
    m = y >= minArea;  x = x(m); y = y(m); z = z(m);
    if nargin < 5
        [X, Y] = meshgrid(unique(x), unique(y));
    end
    Z = nan(size(X));
    for k = 1:numel(x)
        Z(abs(Y(:,1) - y(k)) < 1e-6, abs(X(1,:) - x(k)) < 1e-6) = z(k);
    end
end

function local_axStyle(ax, FS)
% white background, black axes and text (same look as the other dashboards)
    ax.Color     = 'white';
    ax.XColor    = 'black';  ax.YColor = 'black';  ax.ZColor = 'black';
    ax.GridColor = [0.15 0.15 0.15];
    ax.FontSize  = FS - 2;
    ax.LineWidth = 1;
    ax.Box       = 'on';
    grid(ax, 'on');
end

function local_legendStyle(lg, FS)
    lg.Color     = 'white';
    lg.TextColor = 'black';
    lg.EdgeColor = [0.6 0.6 0.6];
    lg.FontSize  = FS - 2;
end

function local_meshStyle(ax, FS, zlab, ttl)
    local_axStyle(ax, FS);
    view(ax, -40, 25);
    xlabel(ax, 'Budget [₪×10^{11}]',     'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black');
    ylabel(ax, 'Solar land cap [km^2]',  'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black');
    zlabel(ax, zlab,                     'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black');
    title(ax, ttl, 'FontWeight', 'bold', 'FontSize', FS + 2, 'Color', 'black');
    axis(ax, 'tight');
end

function local_costStyle(ax, FS, ttl)
    local_axStyle(ax, FS);
    xlabel(ax, 'Solar land cap [km^2]',               'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black');
    ylabel(ax, 'Average system cost 2050 [NIS/kWh]',  'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black');
    title(ax, ttl, 'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black');
    xticks(ax, [100 400:50:850]);
end

function R = local_repCosts(K, scenRoot, B, Blow, lowMax)
% Representative scenarios (fixed budget, one per land cap) and their 2050 costs.
    areas = unique(K.MaxAreaSolar);
    R = struct('area', [], 're', [], 'direct', [], 'social', []);
    for a = areas(:)'
        b = B;  if a <= lowMax, b = Blow; end
        j = find(K.MaxAreaSolar == a & abs(K.MaxCost - b) < 1e6, 1);
        if isempty(j)
            warning('Missing representative scenario: %d km2 at %.0f x10^9', a, b/1e9);
            continue
        end
        resFile = fullfile(scenRoot, char(string(K.Scenario(j))), 'results_heavy.mat');
        if ~isfile(resFile)
            warning('File not found: %s', resFile);
            continue
        end
        S   = load(resFile, 'RES');  RES = S.RES;
        y   = 2050 - RES.BaseYear + 1;
        df  = RES.P.df_yearly(y);
        dir = (sum(RES.opCostYearBySource(:, y)) + sum(RES.buildCostYearBySource(:, y))) / df;   % NIS, undiscounted
        car = sum(RES.extCostYearBySource(:, y)) / df;                                          % NIS, undiscounted
        E   = max(1, RES.elecYear(y));                                                          % MWh
        R.area(end+1, 1)   = a;
        R.re(end+1, 1)     = K.RenewablesPct2050(j);
        R.direct(end+1, 1) = dir / E / 1000;          % NIS/kWh
        R.social(end+1, 1) = (dir + car) / E / 1000;  % NIS/kWh
    end
end

function local_diffHeatmap(ax, K0, K1, FS)
% Cumulative emissions avoided by nuclear [MtCO2e] = no-nuclear minus nuclear,
% for every budget x land cell (including the 100 km2 benchmark).
    x0 = round(K0.MaxCost/1e11, 2);  x1 = round(K1.MaxCost/1e11, 2);
    xs = unique([x0; x1]);  ys = unique([K0.MaxAreaSolar; K1.MaxAreaSolar]);
    E0 = nan(numel(ys), numel(xs));  E1 = E0;
    for k = 1:height(K0), E0(ys == K0.MaxAreaSolar(k), xs == x0(k)) = K0.TotalEmissions_AllYears(k)/1e6; end
    for k = 1:height(K1), E1(ys == K1.MaxAreaSolar(k), xs == x1(k)) = K1.TotalEmissions_AllYears(k)/1e6; end
    D = E0 - E1;                                   % positive = nuclear avoids emissions

    local_axStyle(ax, FS);
    hold(ax, 'on');
    imagesc(ax, 1:numel(xs), 1:numel(ys), D, 'AlphaData', ~isnan(D));
    set(ax, 'YDir', 'normal');
    nC = 256;                                      % white-to-dark-red colormap
    reds = [linspace(1.00, 0.45, nC)', linspace(0.96, 0.00, nC)', linspace(0.94, 0.00, nC)'];
    colormap(ax, reds);                            % larger saving = darker red
    v = D(isfinite(D));  caxis(ax, [min(v) max(v)]);  lim = caxis(ax);

    for i = 1:numel(ys)
        for j = 1:numel(xs)
            if isfinite(D(i,j))
                t = (D(i,j) - lim(1)) / max(diff(lim), eps);
                col = [1 1 1] * (t > 0.5);         % white text on dark cells
                txt = sprintf('%.0f', D(i,j));
            elseif isfinite(E1(i,j))
                col = [0.4 0.4 0.4];  txt = 'nuclear only';
            else
                col = [0.5 0.5 0.5];  txt = 'infeasible';
            end
            text(ax, j, i, txt, 'HorizontalAlignment', 'center', 'FontSize', FS-5, ...
                'FontWeight', 'bold', 'Color', col);
        end
    end

    xticks(ax, 1:numel(xs));  xticklabels(ax, compose('%d', round(xs * 100)));
    yticks(ax, 1:numel(ys));  yticklabels(ax, compose('%d', ys));
    xlim(ax, [0.5 numel(xs)+0.5]);  ylim(ax, [0.5 numel(ys)+0.5]);
    grid(ax, 'off');  view(ax, 2);
    xlabel(ax, 'Budget [₪×10^{11}]',    'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black');
    ylabel(ax, 'Solar land cap [km^2]', 'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black');
    title(ax, 'Cumulative emissions 2023–2050 avoided by nuclear [MtCO_2e] (without – with nuclear)', ...
        'FontWeight', 'bold', 'FontSize', FS+1, 'Color', 'black');
    cb = colorbar(ax);  cb.Color = 'black';  cb.FontSize = FS-2;
    cb.Label.String = 'Avoided emissions [MtCO_2e]';  cb.Label.FontWeight = 'bold';
end
