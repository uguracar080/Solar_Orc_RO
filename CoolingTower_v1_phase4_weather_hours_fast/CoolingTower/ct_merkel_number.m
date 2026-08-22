function CTOutput = ct_merkel_number(CTMode, CTInput, CTConfig)
% CT_MERKEL_NUMBER  Classical Merkel integral, forward or inverse.
%
% Naming is component-scoped throughout the project:
%   CTInput.Me_available   (not data.Me_available)
%   CTOutput.Me_required
%   CTConfig.numerics.*
%
% Required CTInput fields
%   T_w_in_C
%   ambient          : CTAmbient structure for ct_psychrometrics
%   and either L_over_G or (mdot_water, mdot_dry_air)
%
% Forward mode additionally requires
%   CTInput.T_w_out_C
%
% Inverse mode additionally requires
%   CTInput.Me_available

if nargin < 3 || isempty(CTConfig)
    CTConfig = ct_default_config();
end
CTMode = char(CTMode);
if strcmpi(CTMode,'forward')
    CTModeKey = 'forward';
elseif strcmpi(CTMode,'inverse')
    CTModeKey = 'inverse';
else
    error('ct_merkel_number:Mode','CTMode must be forward or inverse.');
end

required = {'T_w_in_C','ambient'};
for k = 1:numel(required)
    if ~isfield(CTInput,required{k})
        error('ct_merkel_number:MissingField','Missing CTInput.%s',required{k});
    end
end

CTAir = ct_psychrometrics(CTInput.ambient,CTConfig);
if numel(CTAir.h_Jkgda) ~= 1
    error('ct_merkel_number:ScalarOnly','Phase-1 Merkel solver expects a scalar CT operating point.');
end

LoverG = resolve_L_over_G(CTInput);
Tw_in = CTInput.T_w_in_C;
Twb = CTAir.T_wb_C;
CTNumerics = CTConfig.numerics;

if Tw_in <= Twb + CTNumerics.min_approach_C
    CTOutput = base_output();
    CTOutput.T_w_out_C = Tw_in;
    CTOutput.Me_required = 0;
    CTOutput.L_over_G = LoverG;
    CTOutput.h_air_in_Jkgda = CTAir.h_Jkgda;
    CTOutput.feasible = false;
    CTOutput.status = 'NO_THERMAL_DRIVING_FORCE';
    CTOutput.air_in = CTAir;
    return
end

switch CTModeKey
    case 'forward'
        if ~isfield(CTInput,'T_w_out_C')
            error('ct_merkel_number:MissingField','Forward mode requires CTInput.T_w_out_C.');
        end
        Tw_out = CTInput.T_w_out_C;
        cp = ct_water_properties(0.5*(Tw_in + Tw_out),CTConfig).cp_JkgK;
        CTCalc = merkel_forward(Tw_out,Tw_in,CTAir.h_Jkgda,LoverG, ...
            CTInput.ambient.P_atm_Pa,cp,CTConfig);
        CTOutput = package_output(Tw_out,LoverG,CTAir,CTCalc);

    case 'inverse'
        if ~isfield(CTInput,'Me_available')
            error('ct_merkel_number:MissingField','Inverse mode requires CTInput.Me_available.');
        end
        Me_available = CTInput.Me_available;
        if ~isfinite(Me_available) || Me_available < 0
            error('ct_merkel_number:Me','CTInput.Me_available must be finite and nonnegative.');
        end

        cp = ct_water_properties(Tw_in,CTConfig).cp_JkgK;
        T_lower = Twb + CTNumerics.min_approach_C;
        T_upper = Tw_in - 1e-4;
        CTCalcLow = merkel_forward(T_lower,Tw_in,CTAir.h_Jkgda,LoverG, ...
            CTInput.ambient.P_atm_Pa,cp,CTConfig);
        if CTCalcLow.feasible && Me_available >= CTCalcLow.Me
            CTOutput = package_output(T_lower,LoverG,CTAir,CTCalcLow);
            CTOutput.status = 'APPROACH_LIMIT';
            CTOutput.Me_available = Me_available;
            return
        end

        residual = @(T) residual_safe(T,Tw_in,CTAir.h_Jkgda,LoverG, ...
            CTInput.ambient.P_atm_Pa,cp,CTConfig,Me_available);
        fL = residual(T_lower); fU = residual(T_upper);
        if ~isfinite(fL) || ~isfinite(fU) || sign(fL) == sign(fU)
            CTOutput = package_output(NaN,LoverG,CTAir,CTCalcLow);
            CTOutput.feasible = false;
            CTOutput.status = 'NO_BRACKET';
            CTOutput.Me_available = Me_available;
            CTOutput.diagnostics.residual_lower = fL;
            CTOutput.diagnostics.residual_upper = fU;
            return
        end

        Tw_out = fzero(residual,[T_lower T_upper]);
        CTCalc = merkel_forward(Tw_out,Tw_in,CTAir.h_Jkgda,LoverG, ...
            CTInput.ambient.P_atm_Pa,cp,CTConfig);
        CTOutput = package_output(Tw_out,LoverG,CTAir,CTCalc);
        CTOutput.Me_available = Me_available;
end
end

function LoverG = resolve_L_over_G(CTInput)
if isfield(CTInput,'L_over_G')
    LoverG = CTInput.L_over_G;
elseif isfield(CTInput,'mdot_water') && isfield(CTInput,'mdot_dry_air')
    LoverG = CTInput.mdot_water/CTInput.mdot_dry_air;
else
    error('ct_merkel_number:FlowRatio', ...
        'Provide CTInput.L_over_G or CTInput.mdot_water and CTInput.mdot_dry_air.');
end
if ~isfinite(LoverG) || LoverG <= 0
    error('ct_merkel_number:FlowRatio','CTInput L/G must be finite and positive.');
end
end

function CTCalc = merkel_forward(Tw_out,Tw_in,h_air_in,LoverG,P,cp,CTConfig)
CTNumerics = CTConfig.numerics;
CTCalc = struct('Me',NaN,'feasible',false,'status','INVALID', ...
    'minDeltaH',NaN,'T_vec',[],'h_sat_vec',[],'h_air_bulk_vec',[],'integrand',[]);
if ~isfinite(Tw_out) || Tw_out >= Tw_in
    CTCalc.status = 'INVALID_WATER_TEMPERATURES'; return
end
T = linspace(Tw_out,Tw_in,round(CTNumerics.merkel_n_intervals));
hsat = saturated_air_enthalpy(T,P,CTConfig);
hbulk = h_air_in + LoverG*cp*(T-Tw_out);
dH = hsat-hbulk;
CTCalc.minDeltaH = min(dH);
CTCalc.T_vec = T; CTCalc.h_sat_vec = hsat; CTCalc.h_air_bulk_vec = hbulk;
if any(~isfinite(dH)) || any(dH <= CTNumerics.min_enthalpy_potential_Jkgda)
    CTCalc.Me = Inf; CTCalc.status = 'ENTHALPY_PINCH'; return
end
CTCalc.integrand = cp./dH;
CTCalc.Me = trapz(T,CTCalc.integrand);
CTCalc.feasible = isfinite(CTCalc.Me) && CTCalc.Me >= 0;
if CTCalc.feasible, CTCalc.status = 'OK'; else, CTCalc.status = 'NUMERICAL_FAIL'; end
end

function F = residual_safe(Tw_out,Tw_in,h_air_in,LoverG,P,cp,CTConfig,Me_available)
CTCalc = merkel_forward(Tw_out,Tw_in,h_air_in,LoverG,P,cp,CTConfig);
if ~CTCalc.feasible, F = 1e12; else, F = CTCalc.Me-Me_available; end
end

function hsat = saturated_air_enthalpy(T_C,P,CTConfig)
backend = char(CTConfig.psychrometrics.backend);
if strcmpi(backend,'coolprop') || strcmpi(backend,'auto')
    try
        hsat = double(HAPropsSI('H','T',T_C+273.15,'P',P,'R',1.0));
        hsat = reshape(hsat,size(T_C));
        if all(isfinite(hsat(:))), return; end
    catch ME
        if strcmpi(backend,'coolprop'), rethrow(ME); end
    end
end
pws = 611.21.*exp((18.678-T_C./234.5).*(T_C./(257.14+T_C)));
omega = 0.62198.*pws./max(P-pws,1e-9);
hsat = 1006.*T_C + omega.*(2501000+1860.*T_C);
end

function CTOutput = package_output(Tw_out,LoverG,CTAir,CTCalc)
CTOutput = base_output();
CTOutput.T_w_out_C = Tw_out;
CTOutput.Me_required = CTCalc.Me;
CTOutput.L_over_G = LoverG;
CTOutput.h_air_in_Jkgda = CTAir.h_Jkgda;
CTOutput.min_enthalpy_potential_Jkgda = CTCalc.minDeltaH;
CTOutput.feasible = CTCalc.feasible;
CTOutput.status = CTCalc.status;
CTOutput.air_in = CTAir;
CTOutput.diagnostics.T_vec_C = CTCalc.T_vec;
CTOutput.diagnostics.h_sat_vec_Jkgda = CTCalc.h_sat_vec;
CTOutput.diagnostics.h_air_bulk_vec_Jkgda = CTCalc.h_air_bulk_vec;
CTOutput.diagnostics.integrand = CTCalc.integrand;
end

function CTOutput = base_output()
CTOutput = struct();
CTOutput.T_w_out_C = NaN;
CTOutput.Me_required = NaN;
CTOutput.Me_available = NaN;
CTOutput.L_over_G = NaN;
CTOutput.h_air_in_Jkgda = NaN;
CTOutput.min_enthalpy_potential_Jkgda = NaN;
CTOutput.feasible = false;
CTOutput.status = 'UNINITIALIZED';
CTOutput.air_in = struct();
CTOutput.diagnostics = struct();
end
