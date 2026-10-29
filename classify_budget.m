function [status, gapPct] = classify_budget(maxCost, costMin, costMinStatus)
% CLASSIFY_BUDGET  Decide whether an emissions scenario is worth solving.
%   [status, gapPct] = classify_budget(maxCost, costMin, costMinStatus)
%   maxCost       : scenario budget [NIS]
%   costMin       : cost-min of the same land cap [NIS] (NaN if unknown)
%   costMinStatus : Gurobi status of that cost-min solve
%   status : "RUN"                - solve the scenario
%            "INFEASIBLE_BUDGET"  - budget below the cost-min (cannot be feasible)
%            "INFEASIBLE_COSTMIN" - the land cap is infeasible at any budget
%   gapPct : budget relative to the cost-min [%] (negative = shortfall)
%   If the cost-min is unknown or failed, the scenario is solved (never skipped
%   on missing information). Tolerance 1e-6 relative: a budget equal to the
%   cost-min (to solver precision) is solved.
    tol    = 1e-6;
    costMinStatus = string(costMinStatus);
    gapPct = NaN;
    if costMinStatus == "OPTIMAL" && isfinite(costMin) && costMin > 0
        gapPct = 100 * (maxCost / costMin - 1);
        if maxCost < costMin * (1 - tol)
            status = "INFEASIBLE_BUDGET";
        else
            status = "RUN";
        end
    elseif any(costMinStatus == ["INFEASIBLE", "INF_OR_UNBD"])
        status = "INFEASIBLE_COSTMIN";
    else
        status = "RUN";
    end
end
