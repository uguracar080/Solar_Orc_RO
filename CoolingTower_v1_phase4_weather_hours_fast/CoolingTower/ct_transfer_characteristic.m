function CTTransfer = ct_transfer_characteristic(CTInput, CTDesign, CTConfig)
% CT_TRANSFER_CHARACTERISTIC  Off-design available Merkel characteristic.
%
% Phase-2 correlation:
%   Me_off/Me_r = r_w^(0.43177-1) * r_a^0.641400 * (T_w_in/T_w_in,r)^0.178670
%
% where r_w = mdot_water/mdot_water_rated and r_a = mdot_air/mdot_air_rated.
% This is the normalized form of the reported Kloppers-Kroger trickle-fill
% Ka correlation, converted to Me because Me = KaV/L.

if nargin < 3 || isempty(CTConfig)
    CTConfig = ct_default_config();
end

if ~isfield(CTInput,'T_w_in_C')
    error('ct_transfer_characteristic:MissingField','Missing CTInput.T_w_in_C.');
end

mdot_water = getfield_default(CTInput,'mdot_water',CTDesign.mdot_water_rated);
if isfield(CTInput,'mdot_air') && ~isempty(CTInput.mdot_air)
    mdot_air = CTInput.mdot_air;
elseif isfield(CTInput,'mdot_dry_air') && ~isempty(CTInput.mdot_dry_air)
    mdot_air = CTInput.mdot_dry_air;
elseif isfield(CTInput,'fan_ratio') && ~isempty(CTInput.fan_ratio)
    mdot_air = CTDesign.mdot_air_rated*CTInput.fan_ratio;
else
    mdot_air = CTDesign.mdot_air_rated;
end

rw = mdot_water/CTDesign.mdot_water_rated;
ra = mdot_air/CTDesign.mdot_air_rated;

CTTransfer = struct();
CTTransfer.component = 'CT';
CTTransfer.correlation = CTConfig.transfer.correlation;
CTTransfer.mdot_water = mdot_water;
CTTransfer.mdot_air = mdot_air;
CTTransfer.water_flow_ratio = rw;
CTTransfer.air_flow_ratio = ra;
CTTransfer.T_w_in_C = CTInput.T_w_in_C;
CTTransfer.Me_available = NaN;
CTTransfer.feasible = false;
CTTransfer.status = 'UNINITIALIZED';

if ~isfinite(rw) || rw <= 0
    CTTransfer.status = 'INVALID_WATER_FLOW'; return
end
if ~isfinite(ra) || ra <= 0
    CTTransfer.Me_available = 0;
    CTTransfer.status = 'NO_AIR_FLOW';
    return
end

if strcmpi(CTConfig.transfer.correlation,'constant_me')
    Me_available = CTDesign.Me_rated;
    temperature_ratio = 1;
elseif strcmpi(CTConfig.transfer.correlation,'kloppers_trickle_normalized')
    temperature_ratio = make_temperature_ratio(CTInput.T_w_in_C, CTDesign.T_w_in_rated_C, CTConfig);
    Me_available = CTDesign.Me_rated * ...
        rw^(CTConfig.transfer.Me_water_exponent) * ...
        ra^(CTConfig.transfer.Me_air_exponent) * ...
        temperature_ratio^(CTConfig.transfer.Me_Twin_exponent);
else
    error('ct_transfer_characteristic:Correlation', ...
        'Unknown CTConfig.transfer.correlation: %s', CTConfig.transfer.correlation);
end

CTTransfer.temperature_ratio = temperature_ratio;
CTTransfer.Me_available = Me_available;
CTTransfer.feasible = isfinite(Me_available) && Me_available >= 0;
if CTTransfer.feasible
    CTTransfer.status = 'OK';
else
    CTTransfer.status = 'NUMERICAL_FAIL';
end
end

function val = getfield_default(S, fieldName, defaultVal)
if isfield(S,fieldName) && ~isempty(S.(fieldName))
    val = S.(fieldName);
else
    val = defaultVal;
end
end
function ratio = make_temperature_ratio(T, Tref, CTConfig)
if strcmpi(CTConfig.transfer.temperature_ratio_basis,'Kelvin')
    ratio = (T+273.15)/(Tref+273.15);
else
    ratio = T/Tref;
end
if ~isfinite(ratio) || ratio <= 0
    ratio = 1;
end
end
