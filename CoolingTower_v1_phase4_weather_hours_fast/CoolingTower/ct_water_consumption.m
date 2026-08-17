function CTWaterUse = ct_water_consumption(CTInput, CTConfig)
% CT_WATER_CONSUMPTION  Cooling-tower evaporative, drift, blowdown, makeup losses.
%
% Evaporation is calculated from a dry-air basis humidity balance:
%   mdot_evap = mdot_dry_air*(omega_out - omega_in)
%
% Drift and cycles of concentration are project/user assumptions, not part
% of the Merkel thermal calculation.
%
% Required CTInput fields, either explicitly or inside air_in/air_out:
%   mdot_water
%   mdot_air or mdot_dry_air
%   omega_air_in and omega_air_out, or air_in.omega and air_out.omega

if nargin < 2 || isempty(CTConfig)
    CTConfig = ct_default_config();
end

mdot_water = getfield_default(CTInput,'mdot_water',NaN);
mdot_air = resolve_mdot_air(CTInput);
omega_in = resolve_omega(CTInput,'in');
omega_out = resolve_omega(CTInput,'out');
tower_active = getfield_default(CTInput,'tower_active',true);

rho_w = CTConfig.water.rho_kgm3;
drift_fraction = CTConfig.water_consumption.drift_fraction;
COC = CTConfig.water_consumption.cycles_of_concentration;
if isfield(CTConfig.water_consumption,'enabled') && ~CTConfig.water_consumption.enabled
    tower_active = false;
end

CTWaterUse = base_output();
CTWaterUse.mdot_water = mdot_water;
CTWaterUse.mdot_dry_air = mdot_air;
CTWaterUse.omega_air_in = omega_in;
CTWaterUse.omega_air_out = omega_out;
CTWaterUse.drift_fraction = drift_fraction;
CTWaterUse.cycles_of_concentration = COC;
CTWaterUse.tower_active = tower_active;

if ~isfinite(mdot_water) || mdot_water < 0
    CTWaterUse.status = 'INVALID_WATER_FLOW'; return
end
if ~isfinite(mdot_air) || mdot_air < 0
    CTWaterUse.status = 'INVALID_AIR_FLOW'; return
end
if ~isfinite(omega_in) || ~isfinite(omega_out)
    CTWaterUse.status = 'INVALID_HUMIDITY_RATIO'; return
end

if ~tower_active || mdot_water == 0 || mdot_air == 0
    CTWaterUse.mdot_evap_kg_s = 0;
    CTWaterUse.mdot_drift_kg_s = 0;
    CTWaterUse.mdot_blowdown_kg_s = 0;
    CTWaterUse.mdot_makeup_kg_s = 0;
    CTWaterUse.purge_required_kg_s = 0;
    CTWaterUse.V_evap_m3_h = 0;
    CTWaterUse.V_drift_m3_h = 0;
    CTWaterUse.V_blowdown_m3_h = 0;
    CTWaterUse.V_makeup_m3_h = 0;
    CTWaterUse.feasible = true;
    if isfield(CTConfig.water_consumption,'enabled') && ~CTConfig.water_consumption.enabled
        CTWaterUse.status = 'WATER_CONSUMPTION_DISABLED';
    else
        CTWaterUse.status = 'TOWER_INACTIVE_NO_WATER_LOSS';
    end
    return
end

mdot_evap = max(0, mdot_air*(omega_out - omega_in));
mdot_drift = max(0, drift_fraction*mdot_water);

if isfinite(COC) && COC > 1
    purge_required = mdot_evap/(COC - 1);
    mdot_blowdown = max(0, purge_required - mdot_drift);
    if mdot_drift > purge_required && mdot_evap > 0
        status = 'DRIFT_EXCEEDS_PURGE_REQUIREMENT';
    else
        status = 'OK';
    end
else
    purge_required = NaN;
    mdot_blowdown = 0;
    if mdot_evap == 0 && mdot_drift == 0
        status = 'NO_WATER_LOSS';
    else
        status = 'NO_COC_SPECIFIED';
    end
end

mdot_makeup = mdot_evap + mdot_drift + mdot_blowdown;

CTWaterUse.mdot_evap_kg_s = mdot_evap;
CTWaterUse.mdot_drift_kg_s = mdot_drift;
CTWaterUse.mdot_blowdown_kg_s = mdot_blowdown;
CTWaterUse.mdot_makeup_kg_s = mdot_makeup;
CTWaterUse.purge_required_kg_s = purge_required;

CTWaterUse.V_evap_m3_h = mdot_evap/rho_w*3600;
CTWaterUse.V_drift_m3_h = mdot_drift/rho_w*3600;
CTWaterUse.V_blowdown_m3_h = mdot_blowdown/rho_w*3600;
CTWaterUse.V_makeup_m3_h = mdot_makeup/rho_w*3600;

CTWaterUse.feasible = true;
CTWaterUse.status = status;
end

function val = getfield_default(S, fieldName, defaultVal)
if isfield(S,fieldName) && ~isempty(S.(fieldName))
    val = S.(fieldName);
else
    val = defaultVal;
end
end

function mdot = resolve_mdot_air(CTInput)
if isfield(CTInput,'mdot_dry_air') && ~isempty(CTInput.mdot_dry_air)
    mdot = CTInput.mdot_dry_air;
elseif isfield(CTInput,'mdot_air') && ~isempty(CTInput.mdot_air)
    mdot = CTInput.mdot_air;
else
    mdot = NaN;
end
end

function omega = resolve_omega(CTInput,whichEnd)
if strcmpi(whichEnd,'in')
    if isfield(CTInput,'omega_air_in') && ~isempty(CTInput.omega_air_in)
        omega = CTInput.omega_air_in; return
    elseif isfield(CTInput,'air_in') && isfield(CTInput.air_in,'omega')
        omega = CTInput.air_in.omega; return
    end
else
    if isfield(CTInput,'omega_air_out') && ~isempty(CTInput.omega_air_out)
        omega = CTInput.omega_air_out; return
    elseif isfield(CTInput,'air_out') && isfield(CTInput.air_out,'omega')
        omega = CTInput.air_out.omega; return
    end
end
omega = NaN;
end

function CTWaterUse = base_output()
CTWaterUse = struct();
CTWaterUse.component = 'CT';
CTWaterUse.mdot_water = NaN;
CTWaterUse.mdot_dry_air = NaN;
CTWaterUse.omega_air_in = NaN;
CTWaterUse.omega_air_out = NaN;
CTWaterUse.drift_fraction = NaN;
CTWaterUse.cycles_of_concentration = NaN;
CTWaterUse.tower_active = false;
CTWaterUse.mdot_evap_kg_s = NaN;
CTWaterUse.mdot_drift_kg_s = NaN;
CTWaterUse.mdot_blowdown_kg_s = NaN;
CTWaterUse.mdot_makeup_kg_s = NaN;
CTWaterUse.purge_required_kg_s = NaN;
CTWaterUse.V_evap_m3_h = NaN;
CTWaterUse.V_drift_m3_h = NaN;
CTWaterUse.V_blowdown_m3_h = NaN;
CTWaterUse.V_makeup_m3_h = NaN;
CTWaterUse.feasible = false;
CTWaterUse.status = 'UNINITIALIZED';
end
