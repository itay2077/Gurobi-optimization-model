function PAPER_FIGS()
% PAPER_FIGS  Missing figures for the paper deck (sizes match the slide frames).
%   Slide 14  fig_bound2_capacity.png   installed capacity 2023-2050, Bound 2 (V2-R05)
%   Slide 15  fig_target_vs_budget.png  annual emissions: Bound 1, Bound 2, min-cumulative at the same cost
%   Slide 18  fig_mesh_land_budget.png  MESH: land x budget -> cumulative emissions (V2-R09)
% Requires registry, find_scenarios and find_run_kpi on the path.

    % ---------------- settings ----------------
    V        = 2;
    RUN_B1   = 6;      % least cost
    RUN_B2   = 5;      % cheapest 100% in 2050
    RUN_FB   = 7;      % budget frontier (2,200 km2); budget 495 = same cost as Bound 2
    RUN_GRID = 9;      % land x budget grid
    OUT      = fullfile(pwd, 'paper_figs');
    FS       = 18;     % base font size (figures are pasted 1:1 into the slides)
    LAND_FREE  = 1150; % km2: land no longer binds above this
    LAND_AVAIL = 1129; % km2: published estimate of available land
    TECH = {'Nuclear', 'Solar', 'Gas', 'Coal', 'Battery'};
    TCOL = [0.25 0.35 0.60; 0.90 0.75 0.25; 0.75 0.25 0.25; 0.55 0.35 0.65; 0.30 0.65 0.40];
    if ~isfolder(OUT), mkdir(OUT); end

    % =====================================================================
    % 1) Bound 2: installed capacity by source (slide frame 7.6 x 4.7 in)
    % =====================================================================
    R = local_res(V, RUN_B2, []);
    yrs = R.BaseYear + (0:size(R.capYear, 2) - 1);
    fig = local_fig(7.6, 4.7);  ax = axes(fig);  hold(ax, 'on');
    h = area(ax, yrs, R.capYear' / 1e3, 'LineStyle', 'none');
    for k = 1:5, h(k).FaceColor = TCOL(k,:); end
    lg = legend(ax, flip(h), flip(TECH), 'Location', 'northwest');
    local_labels(ax, FS, 'Year', 'Installed capacity [GW]', '', 'Bound 2: cheapest path to 100% renewables in 2050');
    local_style(ax, FS, lg);  xlim(ax, [yrs(1) yrs(end)]);
    exportgraphics(fig, fullfile(OUT, 'fig_bound2_capacity.png'), 'Resolution', 300);

    % =====================================================================
    % 2) Target vs carbon budget: annual emissions (slide frame 7.6 x 5.2 in)
    % =====================================================================
    P = {RUN_B1, [],  'Least cost (Bound 1)',                [0.45 0.45 0.45];
         RUN_B2, [],  'Cheapest 100% in 2050 (Bound 2)',     [0.75 0.25 0.25];
         RUN_FB, 495, 'Min. cumulative emissions, same cost', [0.25 0.35 0.60]};
    fig = local_fig(7.6, 5.2);  ax = axes(fig);  hold(ax, 'on');
    for k = 1:size(P, 1)
        [R, S] = local_res(V, P{k,1}, P{k,2});
        yrs = R.BaseYear + (0:numel(R.emitYear) - 1);
        plot(ax, yrs, R.emitYear / 1e6, 'LineWidth', 2.5, 'Color', P{k,4}, ...
            'DisplayName', sprintf('%s: %.0f Mt', P{k,3}, S.Emissions_Mt(1)));
    end
    lg = legend(ax, 'Location', 'northeast');
    local_labels(ax, FS, 'Year', 'Annual emissions [MtCO_2e/yr]', '', 'Annual emissions 2023–2050');
    local_style(ax, FS, lg);  xlim(ax, [2023 2050]);
    exportgraphics(fig, fullfile(OUT, 'fig_target_vs_budget.png'), 'Resolution', 300);

    % =====================================================================
    % 3) MESH: land x budget -> cumulative emissions (slide frame 6.0 x 4.4 in)
    % =====================================================================
    [K, ~] = find_run_kpi('Version', V, 'Run', RUN_GRID);
    B = unique(K.MaxCost) / 1e9;  A = unique(K.MaxAreaSolar);
    Z = nan(numel(A), numel(B));
    for i = 1:height(K)
        Z(A == K.MaxAreaSolar(i), abs(B - K.MaxCost(i)/1e9) < 1e-6) = K.TotalEmissions_AllYears(i) / 1e6;
    end
    fig = local_fig(6.0, 4.4);  ax = axes(fig);  hold(ax, 'on');
    surf(ax, B, A, Z, 'FaceAlpha', 0.85, 'EdgeColor', [0.3 0.3 0.3]);
    colormap(ax, parula);  cb = colorbar(ax);
    cb.Label.String = 'MtCO_2e';  cb.Label.FontWeight = 'bold';  cb.Color = 'black';  cb.FontSize = FS - 2;
    % land-availability line drawn on the surface
    zl = interp2(B, A, Z, B, LAND_AVAIL * ones(size(B)));
    plot3(ax, B, LAND_AVAIL * ones(size(B)), zl + 5, 'r-', 'LineWidth', 2.5);
    text(ax, B(end), LAND_AVAIL, zl(end) + 60, sprintf('  available land ≈%d km^2', LAND_AVAIL), ...
        'Color', 'r', 'FontSize', FS - 2, 'FontWeight', 'bold');
    local_labels(ax, FS, 'Budget [₪×10^9]', 'Solar land cap [km^2]', 'Cumulative emissions [MtCO_2e]', ...
        sprintf('Land binds only below ≈%d km^2', LAND_FREE));
    view(ax, -40, 28);  local_style(ax, FS, []);  ax.ZColor = 'black';  axis(ax, 'tight');
    exportgraphics(fig, fullfile(OUT, 'fig_mesh_land_budget.png'), 'Resolution', 300);

    fprintf('Figures written to %s\n', OUT);
end

% =========================================================================
function [R, S] = local_res(V, run, budget)
    args = {'Version', V, 'Run', run};
    if ~isempty(budget), args = [args, {'Budget', budget}]; end
    S = find_scenarios(args{:});
    if height(S) == 0, error('No OPTIMAL scenario for V%d-R%02d (budget %g).', V, run, budget); end
    L = load(char(S.ResultsFile(1)), 'RES');  R = L.RES;
end

function fig = local_fig(w, h)
    fig = figure('Color', 'w', 'Units', 'inches', 'Position', [1 1 w h]);
end

function local_style(ax, FS, lg)
% Same look as the other dashboards: white background, black axes and text, dark grid.
    ax.Color     = 'white';
    ax.XColor    = 'black';  ax.YColor = 'black';
    ax.GridColor = [0.15 0.15 0.15];  ax.GridAlpha = 0.15;
    ax.FontSize  = FS - 2;
    ax.LineWidth = 1;
    ax.Box       = 'on';
    grid(ax, 'on');
    if ~isempty(lg)
        lg.Color = 'white';  lg.TextColor = 'black';  lg.EdgeColor = [0.6 0.6 0.6];  lg.FontSize = FS - 3;
    end
end

function local_labels(ax, FS, xl, yl, zl, ttl)
    xlabel(ax, xl, 'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black');
    ylabel(ax, yl, 'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black');
    if ~isempty(zl), zlabel(ax, zl, 'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black'); end
    if ~isempty(ttl), title(ax, ttl, 'FontWeight', 'bold', 'FontSize', FS, 'Color', 'black'); end
end
