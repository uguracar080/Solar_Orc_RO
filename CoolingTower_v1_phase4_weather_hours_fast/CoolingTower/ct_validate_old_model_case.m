function CTResults = ct_validate_old_model_case(CTConfig)
% CT_VALIDATE_OLD_MODEL_CASE  Regression against the previous CT model.
if nargin < 1 || isempty(CTConfig)
    CTConfig = ct_default_config();
end

Tdb = 35.0; Twb = 24.0; P = 101325;
approach = 4.0; range = 5.0;
cp = CTConfig.water.cp_JkgK;
Qdesign = 2217000*2;
Tw_out = Twb+approach; Tw_in = Tw_out+range;
mdot_w = Qdesign/(cp*range);
LG = [0.5;1.0;1.5;2.0];

CTAmbient = struct('T_db_C',Tdb,'T_wb_C',Twb,'P_atm_Pa',P);
CTAir = ct_psychrometrics(CTAmbient,CTConfig);
T = linspace(Tw_out,Tw_in,400);
hsat = local_hsat(T,P,CTConfig);
Me_old = trapz(T,cp./(hsat-CTAir.h_Jkgda));

Me_new = nan(size(LG)); minDH = nan(size(LG)); status = cell(size(LG));
mdot_air = mdot_w./LG;
CTConfigValidation = CTConfig;
CTConfigValidation.numerics.merkel_n_intervals = 400;

for i = 1:numel(LG)
    CTInput = struct();
    CTInput.T_w_in_C = Tw_in;
    CTInput.T_w_out_C = Tw_out;
    CTInput.L_over_G = LG(i);
    CTInput.ambient = CTAmbient;
    CTOutput = ct_merkel_number('forward',CTInput,CTConfigValidation);
    Me_new(i) = CTOutput.Me_required;
    minDH(i) = CTOutput.min_enthalpy_potential_Jkgda;
    status{i} = char(CTOutput.status);
end

relative_difference_pct = 100*(Me_new/Me_old-1);
comparison = table(LG,mdot_air,Me_new,relative_difference_pct,minDH,status, ...
    'VariableNames',{'L_over_G','mdot_dry_air_kg_s','Me_proper', ...
    'Difference_vs_old_pct','Min_enthalpy_potential_J_kgda','Status'});

fprintf('\n============================================================\n');
fprintf('OLD COOLING-TOWER REGRESSION CASE\n');
fprintf('============================================================\n');
fprintf('Q_design             = %.3f MW\n',Qdesign/1e6);
fprintf('Tdb / Twb            = %.2f / %.2f C\n',Tdb,Twb);
fprintf('Water in / out       = %.2f / %.2f C\n',Tw_in,Tw_out);
fprintf('Water mass flow      = %.3f kg/s\n',mdot_w);
fprintf('Old simplified Me    = %.6f\n',Me_old);
disp(comparison);

CTInputF = struct('T_w_in_C',Tw_in,'T_w_out_C',Tw_out,'L_over_G',1.0,'ambient',CTAmbient);
CTOutputF = ct_merkel_number('forward',CTInputF,CTConfigValidation);
CTInputI = rmfield(CTInputF,'T_w_out_C');
CTInputI.Me_available = CTOutputF.Me_required;
CTOutputI = ct_merkel_number('inverse',CTInputI,CTConfigValidation);
self_error_K = abs(CTOutputI.T_w_out_C-Tw_out);
fprintf('Forward/inverse self-check at L/G = 1: error = %.6g K (%s)\n', ...
    self_error_K,CTOutputI.status);

CTResults = struct();
CTResults.design.Q_design_W = Qdesign;
CTResults.design.T_db_C = Tdb;
CTResults.design.T_wb_C = Twb;
CTResults.design.T_w_in_C = Tw_in;
CTResults.design.T_w_out_C = Tw_out;
CTResults.design.mdot_water = mdot_w;
CTResults.Me_old_simplified = Me_old;
CTResults.comparison = comparison;
CTResults.forward_inverse_error_K = self_error_K;
CTResults.backend = char(CTConfig.psychrometrics.backend);
end

function hsat = local_hsat(T_C,P,CTConfig)
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
