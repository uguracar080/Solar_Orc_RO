function CTWeatherCases = ct_select_weather_test_hours(WeatherData, CTDesign)
% CT_SELECT_WEATHER_TEST_HOURS  Pick representative CT weather stress hours.
%
% The returned table uses row indices into WeatherData. The cases are:
%   MAX_DRY_BULB  : maximum dry-bulb temperature
%   MAX_WET_BULB  : maximum wet-bulb temperature, usually hardest CT hour
%   HOT_DRY       : large wet-bulb depression among warm/hot hours
%   DESIGN_LIKE   : closest to CTDesign rated Tdb/Twb
%   MIN_DRY_BULB  : minimum dry-bulb sanity check

requiredVars = {'T_amb_C','T_wb_C','RH_pct','Patm_Pa'};
for i = 1:numel(requiredVars)
    if ~ismember(requiredVars{i},WeatherData.Properties.VariableNames)
        error('ct_select_weather_test_hours:MissingVariable','WeatherData missing variable: %s',requiredVars{i});
    end
end

Tdb = WeatherData.T_amb_C(:);
Twb = WeatherData.T_wb_C(:);
RH  = WeatherData.RH_pct(:);
P   = WeatherData.Patm_Pa(:);
valid = isfinite(Tdb) & isfinite(Twb) & isfinite(RH) & isfinite(P);

if ~any(valid)
    error('ct_select_weather_test_hours:NoValidRows','No valid weather rows found.');
end

Labels = {'MAX_DRY_BULB'; 'MAX_WET_BULB'; 'HOT_DRY'; 'DESIGN_LIKE'; 'MIN_DRY_BULB'};
Descriptions = { ...
    'Highest dry-bulb temperature'; ...
    'Highest wet-bulb temperature / highest CT stress'; ...
    'Warm hour with large wet-bulb depression'; ...
    'Closest to CT rated Tdb/Twb'; ...
    'Lowest dry-bulb temperature sanity check'};

idx = nan(numel(Labels),1);
used = [];

idx(1) = pick_max(Tdb,valid,used); used(end+1) = idx(1); %#ok<AGROW>
idx(2) = pick_max(Twb,valid,used); used(end+1) = idx(2); %#ok<AGROW>

% Hot-dry: prefer warm/hot hours, then maximize Tdb-Twb.
hotMask = valid & Tdb >= prctile_local(Tdb(valid),75);
if ~any(hotMask)
    hotMask = valid;
end
idx(3) = pick_max(Tdb - Twb,hotMask,used); used(end+1) = idx(3); %#ok<AGROW>

designScore = abs(Tdb - CTDesign.T_db_rated_C) + abs(Twb - CTDesign.T_wb_rated_C);
idx(4) = pick_min(designScore,valid,used); used(end+1) = idx(4); %#ok<AGROW>
idx(5) = pick_min(Tdb,valid,used);

Month = get_weather_var(WeatherData,'Month',idx);
Day   = get_weather_var(WeatherData,'Day',idx);
Hour  = get_weather_var(WeatherData,'Hour',idx);

CTWeatherCases = table();
CTWeatherCases.Label = string(Labels);
CTWeatherCases.Description = string(Descriptions);
CTWeatherCases.WeatherRow = idx;
CTWeatherCases.Month = Month;
CTWeatherCases.Day = Day;
CTWeatherCases.Hour = Hour;
CTWeatherCases.T_db_C = Tdb(idx);
CTWeatherCases.T_wb_C = Twb(idx);
CTWeatherCases.WB_depression_C = Tdb(idx) - Twb(idx);
CTWeatherCases.RH_pct = RH(idx);
CTWeatherCases.P_atm_kPa = P(idx)/1000;
end

function idx = pick_max(score,valid,used)
score = score(:);
valid = valid(:);
score(~valid) = -Inf;
used = used(isfinite(used));
if ~isempty(used)
    score(used) = -Inf;
end
[best,idx] = max(score);
if ~isfinite(best)
    score(:) = -Inf;
    score(valid) = 0;
    [~,idx] = max(score);
end
end

function idx = pick_min(score,valid,used)
score = score(:);
valid = valid(:);
score(~valid) = Inf;
used = used(isfinite(used));
if ~isempty(used)
    score(used) = Inf;
end
[best,idx] = min(score);
if ~isfinite(best)
    score(:) = Inf;
    score(valid) = 0;
    [~,idx] = min(score);
end
end

function x = get_weather_var(WeatherData,varName,idx)
if ismember(varName,WeatherData.Properties.VariableNames)
    v = WeatherData.(varName);
    x = v(idx);
else
    x = nan(size(idx));
end
end

function p = prctile_local(x,q)
x = sort(x(:));
x = x(isfinite(x));
if isempty(x)
    p = NaN;
    return
end
pos = 1 + (numel(x)-1)*q/100;
lo = floor(pos); hi = ceil(pos);
if lo == hi
    p = x(lo);
else
    p = x(lo) + (x(hi)-x(lo))*(pos-lo);
end
end
