function CTAirOut = ct_air_outlet_state(CTInput, CTAmbient, CTConfig)
% CT_AIR_OUTLET_STATE  Outlet moist-air state for the fast CT runtime model.
%
% Runtime Merkel gives water-side cooling and Q_rejected. To estimate
% evaporation, Phase 3 closes the air-side energy balance:
%   h_air_out = h_air_in + Q_rejected/mdot_dry_air
% and, for the fast runtime model, assumes saturated exit air:
%   h_sat(T_air_out,P) = h_air_out.
%
% Required CTInput fields:
%   Q_rejected_W
%   mdot_air or mdot_dry_air
% Optional:
%   air_in       : CTAir structure from ct_psychrometrics
%   T_w_in_C     : used only for a diagnostic / initial bracket
%
% Output CTAirOut fields include T_air_out_C, omega, h_Jkgda, RH, status.

if nargin < 3 || isempty(CTConfig)
    CTConfig = ct_default_config();
end
if ~isfield(CTInput,'Q_rejected_W')
    error('ct_air_outlet_state:MissingField','Missing CTInput.Q_rejected_W.');
end

Q_rejected_W = max(0,CTInput.Q_rejected_W);
mdot_dry_air = resolve_mdot_air(CTInput);

if isfield(CTInput,'air_in') && ~isempty(CTInput.air_in)
    CTAirIn = CTInput.air_in;
else
    CTAirIn = ct_psychrometrics(CTAmbient,CTConfig);
end

CTAirOut = base_output();
CTAirOut.air_in = CTAirIn;
CTAirOut.mdot_dry_air = mdot_dry_air;
CTAirOut.Q_to_air_W = Q_rejected_W;
CTAirOut.h_air_in_Jkgda = CTAirIn.h_Jkgda;
CTAirOut.omega_air_in = CTAirIn.omega;
CTAirOut.P_atm_Pa = CTAmbient.P_atm_Pa;
CTAirOut.model = CTConfig.air_outlet.model;

if mdot_dry_air <= 0 || ~isfinite(mdot_dry_air)
    CTAirOut = copy_inlet_as_outlet(CTAirOut,CTAirIn);
    CTAirOut.feasible = false;
    CTAirOut.status = 'NO_AIR_FLOW';
    return
end

h_target = CTAirIn.h_Jkgda + Q_rejected_W/mdot_dry_air;
CTAirOut.h_air_out_target_Jkgda = h_target;

if Q_rejected_W <= 0
    CTAirOut = copy_inlet_as_outlet(CTAirOut,CTAirIn);
    CTAirOut.h_air_out_target_Jkgda = h_target;
    CTAirOut.feasible = true;
    CTAirOut.status = 'NO_HEAT_TO_AIR';
    return
end

if ~strcmpi(CTConfig.air_outlet.model,'saturated_exit')
    error('ct_air_outlet_state:Model','Unknown CTConfig.air_outlet.model: %s',CTConfig.air_outlet.model);
end

P = CTAmbient.P_atm_Pa;
T_low = max(-60, min(CTAirIn.T_wb_C,CTAirIn.T_db_C) - 40);
T_high_candidates = [CTAirIn.T_db_C+80, CTAirIn.T_wb_C+90, 80];
if isfield(CTInput,'T_w_in_C') && isfinite(CTInput.T_w_in_C)
    T_high_candidates(end+1) = CTInput.T_w_in_C + 40; %#ok<AGROW>
end
T_high = min(99.9, max(T_high_candidates));
if T_high <= T_low
    T_high = min(99.9,T_low+50);
end

f_low = hsat_minus_target(T_low,P,CTConfig,h_target);
f_high = hsat_minus_target(T_high,P,CTConfig,h_target);

if ~isfinite(f_low) || ~isfinite(f_high)
    CTAirOut = copy_inlet_as_outlet(CTAirOut,CTAirIn);
    CTAirOut.feasible = false;
    CTAirOut.status = 'SATURATION_SOLVER_FAIL';
    CTAirOut.diagnostics.f_low = f_low;
    CTAirOut.diagnostics.f_high = f_high;
    return
end

if f_low > 0
    T_out = T_low;
    status = 'SATURATION_LOWER_LIMIT';
elseif f_high < 0
    T_out = T_high;
    status = 'SATURATION_UPPER_LIMIT';
else
    T_out = fzero(@(T) hsat_minus_target(T,P,CTConfig,h_target), [T_low T_high]);
    status = 'OK';
end

CTAmbientSat = struct('T_db_C',T_out,'RH',1.0,'P_atm_Pa',P);
CTAirSat = ct_psychrometrics(CTAmbientSat,CTConfig);

CTAirOut.T_air_out_C = CTAirSat.T_db_C;
CTAirOut.T_db_C = CTAirSat.T_db_C;
CTAirOut.T_wb_C = CTAirSat.T_wb_C;
CTAirOut.RH = CTAirSat.RH;
CTAirOut.RH_pct = CTAirSat.RH_pct;
CTAirOut.omega = CTAirSat.omega;
CTAirOut.omega_air_out = CTAirSat.omega;
CTAirOut.h_Jkgda = CTAirSat.h_Jkgda;
CTAirOut.h_kJkgda = CTAirSat.h_kJkgda;
CTAirOut.h_air_out_Jkgda = CTAirSat.h_Jkgda;
CTAirOut.backend_used = CTAirSat.backend_used;
CTAirOut.h_error_Jkgda = CTAirSat.h_Jkgda - h_target;
CTAirOut.feasible = strcmpi(status,'OK');
CTAirOut.status = status;
end

function mdot = resolve_mdot_air(CTInput)
if isfield(CTInput,'mdot_dry_air') && ~isempty(CTInput.mdot_dry_air)
    mdot = CTInput.mdot_dry_air;
elseif isfield(CTInput,'mdot_air') && ~isempty(CTInput.mdot_air)
    mdot = CTInput.mdot_air;
else
    error('ct_air_outlet_state:MissingField','Provide CTInput.mdot_air or CTInput.mdot_dry_air.');
end
end

function F = hsat_minus_target(T_C,P,CTConfig,h_target)
try
    CTAmbientSat = struct('T_db_C',T_C,'RH',1.0,'P_atm_Pa',P);
    CTAirSat = ct_psychrometrics(CTAmbientSat,CTConfig);
    F = CTAirSat.h_Jkgda - h_target;
catch
    F = NaN;
end
end

function CTAirOut = copy_inlet_as_outlet(CTAirOut,CTAirIn)
CTAirOut.T_air_out_C = CTAirIn.T_db_C;
CTAirOut.T_db_C = CTAirIn.T_db_C;
CTAirOut.T_wb_C = CTAirIn.T_wb_C;
CTAirOut.RH = CTAirIn.RH;
CTAirOut.RH_pct = CTAirIn.RH_pct;
CTAirOut.omega = CTAirIn.omega;
CTAirOut.omega_air_out = CTAirIn.omega;
CTAirOut.h_Jkgda = CTAirIn.h_Jkgda;
CTAirOut.h_kJkgda = CTAirIn.h_kJkgda;
CTAirOut.h_air_out_Jkgda = CTAirIn.h_Jkgda;
CTAirOut.h_error_Jkgda = 0;
CTAirOut.backend_used = CTAirIn.backend_used;
end

function CTAirOut = base_output()
CTAirOut = struct();
CTAirOut.component = 'CT';
CTAirOut.model = '';
CTAirOut.T_air_out_C = NaN;
CTAirOut.T_db_C = NaN;
CTAirOut.T_wb_C = NaN;
CTAirOut.RH = NaN;
CTAirOut.RH_pct = NaN;
CTAirOut.omega = NaN;
CTAirOut.omega_air_in = NaN;
CTAirOut.omega_air_out = NaN;
CTAirOut.h_Jkgda = NaN;
CTAirOut.h_kJkgda = NaN;
CTAirOut.h_air_in_Jkgda = NaN;
CTAirOut.h_air_out_Jkgda = NaN;
CTAirOut.h_air_out_target_Jkgda = NaN;
CTAirOut.h_error_Jkgda = NaN;
CTAirOut.mdot_dry_air = NaN;
CTAirOut.Q_to_air_W = NaN;
CTAirOut.P_atm_Pa = NaN;
CTAirOut.backend_used = '';
CTAirOut.air_in = struct();
CTAirOut.feasible = false;
CTAirOut.status = 'UNINITIALIZED';
end
