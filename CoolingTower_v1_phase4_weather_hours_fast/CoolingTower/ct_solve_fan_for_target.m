function CTOutput = ct_solve_fan_for_target(CTInput, CTAmbient, CTDesign, CTConfig)
% CT_SOLVE_FAN_FOR_TARGET  Minimum fan ratio to meet a cold-water target.
%
% Required CTInput fields:
%   T_w_in_C
%   T_w_out_target_C
% Optional:
%   mdot_water
%
% The function returns the CTOutput from ct_offdesign_merkel at the selected
% fan ratio and adds target diagnostics.

if nargin < 4 || isempty(CTConfig)
    CTConfig = ct_default_config();
end
if ~isfield(CTInput,'T_w_out_target_C')
    error('ct_solve_fan_for_target:MissingField','Missing CTInput.T_w_out_target_C.');
end

Ttarget = CTInput.T_w_out_target_C;
Tin = CTInput.T_w_in_C;
targetTolC = CTConfig.numerics.target_temperature_tolerance_C;

if Ttarget >= Tin
    CTInput0 = CTInput;
    CTInput0.fan_ratio = 0;
    CTOutput = ct_offdesign_merkel(CTInput0,CTAmbient,CTDesign,CTConfig);
    CTOutput.target.T_w_out_target_C = Ttarget;
    CTOutput.target.error_C = CTOutput.T_w_out_C - Ttarget;
    CTOutput.target.met = true;
    CTOutput.status = 'BYPASS_TARGET_ALREADY_MET';
    CTOutput.feasible = true;
    return
end

CTInputMax = CTInput;
CTInputMax.fan_ratio = CTConfig.fan.fan_ratio_max;
CTOutputMax = ct_offdesign_merkel(CTInputMax,CTAmbient,CTDesign,CTConfig);

if ~localTargetMet(CTOutputMax,Ttarget,targetTolC)
    CTOutput = CTOutputMax;
    CTOutput.target.T_w_out_target_C = Ttarget;
    CTOutput.target.error_C = CTOutput.T_w_out_C - Ttarget;
    CTOutput.target.met = false;
    CTOutput.status = 'AIRFLOW_LIMIT_TARGET_NOT_MET';
    CTOutput.feasible = false;
    return
end

CTInputLow = CTInput;
CTInputLow.fan_ratio = CTConfig.numerics.min_fan_ratio_for_solve;
CTOutputLow = ct_offdesign_merkel(CTInputLow,CTAmbient,CTDesign,CTConfig);

if localTargetMet(CTOutputLow,Ttarget,targetTolC)
    CTOutput = CTOutputLow;
    CTOutput.target.T_w_out_target_C = Ttarget;
    CTOutput.target.error_C = CTOutput.T_w_out_C - Ttarget;
    CTOutput.target.met = true;
    CTOutput.status = 'MIN_FAN_TARGET_MET';
    CTOutput.feasible = true;
    return
end

residual = @(fr) fan_residual(fr,CTInput,CTAmbient,CTDesign,CTConfig,Ttarget);
fr_low = CTConfig.numerics.min_fan_ratio_for_solve;
fr_high = CTConfig.fan.fan_ratio_max;
opts = optimset('TolX',CTConfig.numerics.fan_ratio_tolerance,'Display','off');
try
    fan_ratio_star = fzero(residual,[fr_low fr_high],opts);
catch
    CTOutput = CTOutputMax;
    CTOutput.target.T_w_out_target_C = Ttarget;
    CTOutput.target.error_C = CTOutput.T_w_out_C - Ttarget;
    CTOutput.target.met = false;
    CTOutput.status = 'FAN_RATIO_SOLVER_FAILED';
    CTOutput.feasible = false;
    return
end
fan_ratio_star = min(max(fan_ratio_star,CTConfig.fan.fan_ratio_min),CTConfig.fan.fan_ratio_max);

CTInputStar = CTInput;
CTInputStar.fan_ratio = fan_ratio_star;
CTOutput = ct_offdesign_merkel(CTInputStar,CTAmbient,CTDesign,CTConfig);
CTOutput.target.T_w_out_target_C = Ttarget;
CTOutput.target.error_C = CTOutput.T_w_out_C - Ttarget;
CTOutput.target.met = localTargetMet(CTOutput,Ttarget,targetTolC);
if CTOutput.target.met
    CTOutput.status = 'TARGET_MET';
    CTOutput.feasible = true;
elseif fan_ratio_star >= CTConfig.fan.fan_ratio_max - CTConfig.numerics.fan_ratio_tolerance
    CTOutput.status = 'AIRFLOW_LIMIT_TARGET_NOT_MET';
    CTOutput.feasible = false;
else
    CTOutput.status = 'FAN_RATIO_TARGET_NOT_MET';
    CTOutput.feasible = false;
end
end

function tf = localTargetMet(CTOutput,Ttarget,targetTolC)
if ~isfield(CTOutput,'T_w_out_C') || ~isfinite(CTOutput.T_w_out_C)
    tf = false;
else
    % The tower may overcool; only outlet temperatures above target+tolerance fail.
    tf = CTOutput.T_w_out_C <= Ttarget + targetTolC;
end
end

function F = fan_residual(fan_ratio,CTInput,CTAmbient,CTDesign,CTConfig,Ttarget)
CTInputTrial = CTInput;
CTInputTrial.fan_ratio = fan_ratio;
CTOutputTrial = ct_offdesign_merkel(CTInputTrial,CTAmbient,CTDesign,CTConfig);
F = CTOutputTrial.T_w_out_C - Ttarget;
if ~isfinite(F)
    F = 1e6;
end
end
