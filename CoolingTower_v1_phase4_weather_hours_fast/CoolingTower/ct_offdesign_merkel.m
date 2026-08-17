function CTOutput = ct_offdesign_merkel(CTInput, CTAmbient, CTDesign, CTConfig)
% CT_OFFDESIGN_MERKEL  Fixed cooling-tower off-design rating at a given fan ratio.
%
% Required CTInput fields:
%   T_w_in_C          hot water entering cooling tower [degC]
% Optional:
%   mdot_water        [kg/s], default CTDesign.mdot_water_rated
%   fan_ratio         [-], default 1
%   mdot_air/mdot_dry_air [kg_da/s], alternative to fan_ratio
%
% CTAmbient supplies T_db_C, T_wb_C or RH, and P_atm_Pa.

if nargin < 4 || isempty(CTConfig)
    CTConfig = ct_default_config();
end
if ~isfield(CTInput,'T_w_in_C')
    error('ct_offdesign_merkel:MissingField','Missing CTInput.T_w_in_C.');
end

cp = CTConfig.water.cp_JkgK;
mdot_water = getfield_default(CTInput,'mdot_water',CTDesign.mdot_water_rated);
CTAir = ct_psychrometrics(CTAmbient,CTConfig);

CTFan = ct_fan_power(CTInput,CTDesign,CTConfig);

CTOutput = base_output();
CTOutput.T_w_in_C = CTInput.T_w_in_C;
CTOutput.mdot_water = mdot_water;
CTOutput.fan = CTFan;
CTOutput.fan_ratio = CTFan.fan_ratio;
CTOutput.mdot_air = CTFan.mdot_air;
CTOutput.W_fan_W = CTFan.W_fan_W;
CTOutput.air_in = CTAir;
CTOutput.ambient = CTAmbient;

if mdot_water <= 0 || ~isfinite(mdot_water)
    CTOutput.status = 'INVALID_WATER_FLOW';
    CTOutput = attach_air_and_water_outputs(CTOutput,CTAmbient,CTConfig);
    return
end

if CTInput.T_w_in_C <= CTAir.T_wb_C + CTConfig.numerics.min_approach_C
    CTOutput.T_w_out_C = CTInput.T_w_in_C;
    CTOutput.Q_rejected_W = 0;
    CTOutput.range_C = 0;
    CTOutput.approach_C = CTOutput.T_w_out_C - CTAir.T_wb_C;
    CTOutput.feasible = false;
    CTOutput.status = 'NO_THERMAL_DRIVING_FORCE';
    CTOutput = attach_air_and_water_outputs(CTOutput,CTAmbient,CTConfig);
    return
end

if CTFan.fan_ratio <= 0 || CTFan.mdot_air <= 0
    CTOutput.T_w_out_C = CTInput.T_w_in_C;
    CTOutput.Q_rejected_W = 0;
    CTOutput.range_C = 0;
    CTOutput.approach_C = CTOutput.T_w_out_C - CTAir.T_wb_C;
    CTOutput.feasible = true;
    CTOutput.status = 'NO_AIR_FLOW';
    CTOutput = attach_air_and_water_outputs(CTOutput,CTAmbient,CTConfig);
    return
end

CTCharInput = CTInput;
CTCharInput.mdot_water = mdot_water;
CTCharInput.mdot_air = CTFan.mdot_air;
CTTransfer = ct_transfer_characteristic(CTCharInput,CTDesign,CTConfig);
CTOutput.transfer = CTTransfer;
CTOutput.Me_available = CTTransfer.Me_available;

if ~CTTransfer.feasible
    CTOutput.T_w_out_C = CTInput.T_w_in_C;
    CTOutput.Q_rejected_W = 0;
    CTOutput.range_C = 0;
    CTOutput.approach_C = CTOutput.T_w_out_C - CTAir.T_wb_C;
    CTOutput.feasible = false;
    CTOutput.status = CTTransfer.status;
    CTOutput = attach_air_and_water_outputs(CTOutput,CTAmbient,CTConfig);
    return
end

CTMerkelInput = struct();
CTMerkelInput.T_w_in_C = CTInput.T_w_in_C;
CTMerkelInput.Me_available = CTTransfer.Me_available;
CTMerkelInput.mdot_water = mdot_water;
CTMerkelInput.mdot_dry_air = CTFan.mdot_air;
CTMerkelInput.ambient = CTAmbient;
CTMerkelOutput = ct_merkel_number('inverse',CTMerkelInput,CTConfig);

CTOutput.merkel = CTMerkelOutput;
CTOutput.T_w_out_C = CTMerkelOutput.T_w_out_C;
if ~isfinite(CTOutput.T_w_out_C)
    CTOutput.T_w_out_C = CTInput.T_w_in_C;
end
CTOutput.range_C = max(0, CTInput.T_w_in_C - CTOutput.T_w_out_C);
CTOutput.Q_rejected_W = mdot_water*cp*CTOutput.range_C;
CTOutput.approach_C = CTOutput.T_w_out_C - CTAir.T_wb_C;
CTOutput.L_over_G = mdot_water/CTFan.mdot_air;
CTOutput.min_enthalpy_potential_Jkgda = CTMerkelOutput.min_enthalpy_potential_Jkgda;
CTOutput.feasible = CTMerkelOutput.feasible;
CTOutput.status = CTMerkelOutput.status;
if strcmpi(CTOutput.status,'APPROACH_LIMIT')
    CTOutput.feasible = true;
end

CTOutput = attach_air_and_water_outputs(CTOutput,CTAmbient,CTConfig);
end

function CTOutput = attach_air_and_water_outputs(CTOutput,CTAmbient,CTConfig)
% Attach saturated-exit air state and water-consumption diagnostics.
% This keeps the thermal Merkel solver and water-loss bookkeeping separate
% while exposing convenient fields in CTOutput.

if ~isfield(CTOutput,'Q_rejected_W') || ~isfinite(CTOutput.Q_rejected_W)
    CTOutput.Q_rejected_W = 0;
end
if ~isfield(CTOutput,'mdot_air') || ~isfinite(CTOutput.mdot_air)
    CTOutput.mdot_air = 0;
end
if ~isfield(CTOutput,'mdot_water') || ~isfinite(CTOutput.mdot_water)
    CTOutput.mdot_water = 0;
end

CTAirInput = struct();
CTAirInput.Q_rejected_W = CTOutput.Q_rejected_W;
CTAirInput.mdot_air = CTOutput.mdot_air;
CTAirInput.air_in = CTOutput.air_in;
CTAirInput.T_w_in_C = CTOutput.T_w_in_C;
CTAirOut = ct_air_outlet_state(CTAirInput,CTAmbient,CTConfig);

CTWaterInput = struct();
CTWaterInput.mdot_water = CTOutput.mdot_water;
CTWaterInput.mdot_air = CTOutput.mdot_air;
CTWaterInput.air_in = CTOutput.air_in;
CTWaterInput.air_out = CTAirOut;
CTWaterInput.tower_active = CTOutput.Q_rejected_W > 0 && CTOutput.mdot_air > 0;
CTWaterUse = ct_water_consumption(CTWaterInput,CTConfig);

CTOutput.air_out = CTAirOut;
CTOutput.water_consumption = CTWaterUse;

CTOutput.T_air_out_C = CTAirOut.T_air_out_C;
CTOutput.omega_air_in = CTWaterUse.omega_air_in;
CTOutput.omega_air_out = CTWaterUse.omega_air_out;
CTOutput.h_air_in_Jkgda = CTAirOut.h_air_in_Jkgda;
CTOutput.h_air_out_Jkgda = CTAirOut.h_air_out_Jkgda;

CTOutput.mdot_evap_kg_s = CTWaterUse.mdot_evap_kg_s;
CTOutput.mdot_drift_kg_s = CTWaterUse.mdot_drift_kg_s;
CTOutput.mdot_blowdown_kg_s = CTWaterUse.mdot_blowdown_kg_s;
CTOutput.mdot_makeup_kg_s = CTWaterUse.mdot_makeup_kg_s;
CTOutput.V_makeup_m3_h = CTWaterUse.V_makeup_m3_h;
end

function val = getfield_default(S, fieldName, defaultVal)
if isfield(S,fieldName) && ~isempty(S.(fieldName))
    val = S.(fieldName);
else
    val = defaultVal;
end
end
function CTOutput = base_output()
CTOutput = struct();
CTOutput.component = 'CT';
CTOutput.T_w_in_C = NaN;
CTOutput.T_w_out_C = NaN;
CTOutput.mdot_water = NaN;
CTOutput.mdot_air = NaN;
CTOutput.fan_ratio = NaN;
CTOutput.W_fan_W = NaN;
CTOutput.Q_rejected_W = NaN;
CTOutput.range_C = NaN;
CTOutput.approach_C = NaN;
CTOutput.L_over_G = NaN;
CTOutput.Me_available = NaN;
CTOutput.min_enthalpy_potential_Jkgda = NaN;
CTOutput.feasible = false;
CTOutput.status = 'UNINITIALIZED';
CTOutput.ambient = struct();
CTOutput.air_in = struct();
CTOutput.fan = struct();
CTOutput.transfer = struct();
CTOutput.merkel = struct();
CTOutput.air_out = struct();
CTOutput.water_consumption = struct();
CTOutput.T_air_out_C = NaN;
CTOutput.omega_air_in = NaN;
CTOutput.omega_air_out = NaN;
CTOutput.h_air_in_Jkgda = NaN;
CTOutput.h_air_out_Jkgda = NaN;
CTOutput.mdot_evap_kg_s = NaN;
CTOutput.mdot_drift_kg_s = NaN;
CTOutput.mdot_blowdown_kg_s = NaN;
CTOutput.mdot_makeup_kg_s = NaN;
CTOutput.V_makeup_m3_h = NaN;
end
