function CTFan = ct_fan_power(CTInput, CTDesign, CTConfig)
% CT_FAN_POWER  Cooling-tower fan power from rated fan and fan ratio.
%
% Phase 2 uses the VFD affinity-law form:
%   W_fan = W_fan_rated * fan_ratio^3
% where fan_ratio is treated as mdot_air/mdot_air_rated.

if nargin < 3 || isempty(CTConfig)
    CTConfig = ct_default_config();
end

if isfield(CTInput,'fan_ratio') && ~isempty(CTInput.fan_ratio)
    fan_ratio = CTInput.fan_ratio;
elseif isfield(CTInput,'mdot_air') && ~isempty(CTInput.mdot_air)
    fan_ratio = CTInput.mdot_air/CTDesign.mdot_air_rated;
elseif isfield(CTInput,'mdot_dry_air') && ~isempty(CTInput.mdot_dry_air)
    fan_ratio = CTInput.mdot_dry_air/CTDesign.mdot_air_rated;
else
    fan_ratio = 1.0;
end

fan_ratio_raw = fan_ratio;
fan_ratio = min(max(fan_ratio,CTConfig.fan.fan_ratio_min),CTConfig.fan.fan_ratio_max);
mdot_air = CTDesign.mdot_air_rated*fan_ratio;

if strcmpi(CTConfig.fan.model,'affinity_cubic')
    W_fan_W = CTDesign.W_fan_rated_W*fan_ratio^3;
elseif strcmpi(CTConfig.fan.model,'constant')
    W_fan_W = CTDesign.W_fan_rated_W*(fan_ratio > 0);
else
    error('ct_fan_power:FanModel','Unknown CTConfig.fan.model: %s',CTConfig.fan.model);
end

CTFan = struct();
CTFan.component = 'CT';
CTFan.fan_ratio = fan_ratio;
CTFan.fan_ratio_raw = fan_ratio_raw;
CTFan.mdot_air = mdot_air;
CTFan.W_fan_W = W_fan_W;
CTFan.status = 'OK';
if fan_ratio ~= fan_ratio_raw
    CTFan.status = 'FAN_RATIO_CLIPPED';
end
end

