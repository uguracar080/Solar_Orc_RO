function SolarOut = solar_field_ptc_v1(SolarInput,SolarConfig)
%SOLAR_FIELD_PTC_V1 Simplified PTC-only solar field model for system V1.
%
% This file is derived from the old PTC code kept under Solar_Field/eski calisma.
% Old ORC, HX, condenser, plotting, and exergy layers are intentionally not
% included here. The output is a narrow solar-field contract for the system
% driver.

if nargin < 1 || isempty(SolarInput)
    SolarInput = struct();
end
if nargin < 2 || isempty(SolarConfig)
    SolarConfig = struct();
end

SolarConfig = localDefaults(SolarConfig);
SolarOut = localBlankOutput();

Gb = localGet(SolarInput,'DNI_Wm2',0);
Tamb_K = localGet(SolarInput,'T_amb_K',localGet(SolarInput,'T_amb_C',25) + 273.15);
wind_ms = localGet(SolarInput,'WindSpd_ms',1.0);
Tin_K = localGet(SolarInput,'T_HTF_in_K',SolarConfig.T_HTF_in_K);
V_Lmin_1module = localGet(SolarInput,'V_Lmin_1module',SolarConfig.V_Lmin_1module);

SolarOut.T_HTF_in_K = Tin_K;
SolarOut.DNI_Wm2 = Gb;
SolarOut.T_amb_K = Tamb_K;
SolarOut.WindSpd_ms = wind_ms;
SolarOut.V_Lmin_1module = V_Lmin_1module;

if Gb < SolarConfig.min_DNI_Wm2
    SolarOut.T_HTF_out_K = Tin_K;
    SolarOut.mdot_HTF_kg_s = 0;
    SolarOut.Q_useful_W = 0;
    SolarOut.feasible = false;
    SolarOut.status = 'SOLAR_OFF';
    return
end

try
    inPTC = struct();
    inPTC.Gb_Wm2 = Gb;
    inPTC.Vwind_ms = max(wind_ms,0.1);
    inPTC.Tam_K = Tamb_K;
    inPTC.Tin_K = Tin_K;
    inPTC.V_Lmin_1module = V_Lmin_1module;

    opts = localFsolveOptions(SolarConfig);
    field = SolarConfig.field;
    ptc = SolarConfig.ptc;

    solverCacheIn = localGet(SolarInput,'solver_cache',struct());
    ptcField = localSolveFieldSeriesParallel(inPTC,ptc,field, ...
        SolarConfig.Nusselt_multiplier,SolarConfig.sigma,opts,solverCacheIn);

    SolarOut.T_HTF_out_K = ptcField.Th_out_K;
    SolarOut.mdot_HTF_kg_s = ptcField.mdot_hot_kg_s;
    SolarOut.Q_useful_W = max(0,ptcField.Qu_total_W);
    SolarOut.dP_HTF_Pa = ptcField.dP_hot_Pa;
    SolarOut.aperture_area_m2 = ptcField.Aa_total_m2;
    SolarOut.N_series = field.N_series;
    SolarOut.N_parallel = field.N_parallel;
    SolarOut.ptc_field = ptcField;
    SolarOut.solver_cache = ptcField.solver_cache;
    SolarOut.feasible = SolarOut.Q_useful_W > SolarConfig.min_useful_heat_W;
    if SolarOut.feasible
        SolarOut.status = 'OK';
    else
        SolarOut.status = 'LOW_USEFUL_HEAT';
    end
catch ME
    SolarOut.T_HTF_out_K = Tin_K;
    SolarOut.mdot_HTF_kg_s = 0;
    SolarOut.Q_useful_W = 0;
    SolarOut.feasible = false;
    SolarOut.status = ['ERROR: ' ME.identifier];
    SolarOut.message = ME.message;
end

end

function cfg = localDefaults(cfg)
cfg = localSetDefault(cfg,'min_DNI_Wm2',50);
cfg = localSetDefault(cfg,'min_useful_heat_W',100);
cfg = localSetDefault(cfg,'T_HTF_in_K',380.0);
cfg = localSetDefault(cfg,'V_Lmin_1module',56.8);
cfg = localSetDefault(cfg,'Nusselt_multiplier',1.0);
cfg = localSetDefault(cfg,'sigma',5.670374e-8);

if ~isfield(cfg,'field') || isempty(cfg.field)
    cfg.field = struct();
end
cfg.field = localSetDefault(cfg.field,'N_series',12);
cfg.field = localSetDefault(cfg.field,'N_parallel',12);

if ~isfield(cfg,'solver') || isempty(cfg.solver)
    cfg.solver = struct();
end
cfg.solver = localSetDefault(cfg.solver,'FunctionTolerance',1e-6);
cfg.solver = localSetDefault(cfg.solver,'StepTolerance',1e-6);

if ~isfield(cfg,'ptc') || isempty(cfg.ptc)
    cfg.ptc = struct();
end
ptc = cfg.ptc;
ptc = localSetDefault(ptc,'W',5.0);
ptc = localSetDefault(ptc,'L',7.8);
ptc = localSetDefault(ptc,'Aa',39.0);
ptc = localSetDefault(ptc,'Dri',66e-3);
ptc = localSetDefault(ptc,'Dro',70e-3);
ptc = localSetDefault(ptc,'Dci',109e-3);
ptc = localSetDefault(ptc,'Dco',115e-3);
ptc = localSetDefault(ptc,'eps_c',0.86);
ptc = localSetDefault(ptc,'r_mirror',0.83);
ptc = localSetDefault(ptc,'tau_cover',0.95);
ptc = localSetDefault(ptc,'alpha_abs',0.96);
ptc = localSetDefault(ptc,'gamma_int',1.00);
ptc = localSetDefault(ptc,'K_theta',1.0);
ptc.eta_opt = ptc.r_mirror * ptc.tau_cover * ptc.alpha_abs * ptc.gamma_int * ptc.K_theta;
ptc.Ari = pi*ptc.Dri*ptc.L;
ptc.Aro = pi*ptc.Dro*ptc.L;
ptc.Aci = pi*ptc.Dci*ptc.L;
ptc.Aco = pi*ptc.Dco*ptc.L;
cfg.ptc = ptc;
end

function out = localBlankOutput()
out = struct();
out.component = 'Solar_Field_PTC_v1';
out.DNI_Wm2 = NaN;
out.T_amb_K = NaN;
out.WindSpd_ms = NaN;
out.T_HTF_in_K = NaN;
out.T_HTF_out_K = NaN;
out.V_Lmin_1module = NaN;
out.mdot_HTF_kg_s = NaN;
out.Q_useful_W = NaN;
out.dP_HTF_Pa = NaN;
out.aperture_area_m2 = NaN;
out.N_series = NaN;
out.N_parallel = NaN;
out.feasible = false;
out.status = 'UNINITIALIZED';
out.message = '';
out.ptc_field = struct();
out.solver_cache = struct();
end

function opts = localFsolveOptions(SolarConfig)
solverCfg = localGet(SolarConfig,'solver',struct());
funTol = localGet(solverCfg,'FunctionTolerance',1e-6);
stepTol = localGet(solverCfg,'StepTolerance',1e-6);
if exist('optimoptions','file') == 2
    opts = optimoptions('fsolve','Display','none', ...
        'FunctionTolerance',funTol,'StepTolerance',stepTol);
else
    opts = optimset('Display','off','TolFun',funTol,'TolX',stepTol);
end
end

function ptcField = localSolveFieldSeriesParallel(inPTC,ptc,field,R,sigma,opts,solverCacheIn)
Np = field.N_parallel;
Ns = field.N_series;
TinString_K = inPTC.Tin_K;
TinNow_K = TinString_K;
QuString_W = 0;
dPString_Pa = 0;
ToutLast_K = TinNow_K;
x0Prev = [];
moduleGuess = localModuleInitialGuesses(solverCacheIn,Ns);

lastModule = struct('mdot_kg_s',0);
moduleSolution = nan(3,Ns);
for k = 1:Ns
    in = struct();
    in.Gb = inPTC.Gb_Wm2;
    in.Vwind = inPTC.Vwind_ms;
    in.Tam = inPTC.Tam_K;
    in.Tin = TinNow_K;
    in.V_Lmin = inPTC.V_Lmin_1module;

    if all(isfinite(moduleGuess(:,k)))
        x0Use = moduleGuess(:,k);
        x0Use(1) = max(x0Use(1),in.Tin);
        x0Use(3) = max(x0Use(3),in.Tin + 0.5);
        x0Use(2) = min(max(x0Use(2),in.Tam),x0Use(1));
    elseif isempty(x0Prev)
        x0Use = [];
    else
        x0Use = x0Prev;
        x0Use(1) = max(x0Use(1),in.Tin);
        x0Use(3) = max(x0Use(3),in.Tin + 0.5);
        x0Use(2) = min(max(x0Use(2),in.Tam),x0Use(1));
    end

    lastModule = localSolveSingleModule(in,ptc,R,sigma,opts,x0Use);
    TinNow_K = lastModule.Tout_K;
    ToutLast_K = lastModule.Tout_K;
    QuString_W = QuString_W + lastModule.Qu_W;
    dPString_Pa = dPString_Pa + lastModule.dP_abs_Pa;
    x0Prev = [lastModule.Tr_K; lastModule.Tc_K; lastModule.Tout_K];
    moduleSolution(:,k) = x0Prev;
end

ptcField = struct();
ptcField.Th_in_K = TinString_K;
ptcField.Th_out_K = ToutLast_K;
ptcField.mdot_hot_kg_s = Np * lastModule.mdot_kg_s;
ptcField.Qu_total_W = Np * QuString_W;
ptcField.dP_hot_Pa = dPString_Pa;
ptcField.Ns = Ns;
ptcField.Np = Np;
ptcField.Gb_Wm2 = inPTC.Gb_Wm2;
ptcField.Aa_m2 = ptc.Aa;
ptcField.Aa_total_m2 = ptc.Aa * Ns * Np;
ptcField.solver_cache = struct('module_solution',moduleSolution, ...
    'N_series',Ns,'N_parallel',Np,'V_Lmin_1module',inPTC.V_Lmin_1module, ...
    'DNI_Wm2',inPTC.Gb_Wm2,'T_in_K',TinString_K,'T_out_K',ToutLast_K);
end

function moduleGuess = localModuleInitialGuesses(solverCacheIn,Ns)
moduleGuess = nan(3,Ns);
if ~isstruct(solverCacheIn) || ~isfield(solverCacheIn,'module_solution')
    return
end
candidate = solverCacheIn.module_solution;
if ~isnumeric(candidate) || size(candidate,1) ~= 3
    return
end
nUse = min(Ns,size(candidate,2));
moduleGuess(:,1:nUse) = candidate(:,1:nUse);
end

function out = localSolveSingleModule(in,ptc,R,sigma,opts,x0In)
if nargin < 6 || isempty(x0In)
    x0 = [in.Tin + 40; in.Tam + 20; in.Tin + 20];
else
    x0 = x0In(:);
    x0(1) = max(x0(1),in.Tin);
    x0(3) = max(x0(3),in.Tin + 0.5);
    x0(2) = min(max(x0(2),in.Tam),x0(1));
end

f = @(x) localResidualsPtc(x,in.Gb,in.Vwind,in.Tam,in.Tin,in.V_Lmin,R,ptc,sigma);
[x,~,exitflag] = fsolve(f,x0,opts);
if exitflag <= 0
    x0Fallback = [in.Tin + 40; in.Tam + 20; in.Tin + 20];
    x = fsolve(f,x0Fallback,opts);
end

Tr = x(1);
Tc = x(2);
Tout = x(3);

Tfm = 0.5*(in.Tin + Tout);
[rho,cp,k,mu] = syltherm800_properties_v2(Tfm);
V_m3s = in.V_Lmin*1e-3/60;
mdot = rho*V_m3s;
Re = 4*mdot/(pi*ptc.Dri*mu);
Pr = mu*cp/k;
Nu0 = 0.023*(Re^0.8)*(Pr^0.4);
Nu = R*Nu0;
h = Nu*k/ptc.Dri;
Qs = ptc.Aa*in.Gb;
Qabs = Qs*ptc.eta_opt;
Qu = mdot*cp*(Tout - in.Tin);
Aflow = pi*(ptc.Dri^2)/4;
u = mdot/(rho*Aflow);
fr = 1/((0.79*log(Re) - 1.64)^2);
dP = fr*(ptc.L/ptc.Dri)*(0.5*rho*u^2);

out = struct();
out.Tout_K = Tout;
out.Tr_K = Tr;
out.Tc_K = Tc;
out.mdot_kg_s = mdot;
out.Qu_W = Qu;
out.Qabs_W = Qabs;
out.Re = Re;
out.dP_abs_Pa = dP;
out.h_i_Wm2K = h;
end

function F = localResidualsPtc(x,Gb,Vwind,Tam,Tin,V_Lmin,R,ptc,sigma)
Tr = x(1);
Tc = x(2);
Tout = x(3);

Tfm = 0.5*(Tin + Tout);
[rho,cp,k,mu] = syltherm800_properties_v2(Tfm);

V_m3s = V_Lmin*1e-3/60;
mdot = rho*V_m3s;
Re = 4*mdot/(pi*ptc.Dri*mu);
Pr = mu*cp/k;
Nu0 = 0.023*(Re^0.8)*(Pr^0.4);
Nu = R*Nu0;
h = Nu*k/ptc.Dri;

Qs = ptc.Aa*Gb;
Qabs = Qs*ptc.eta_opt;
Qu = mdot*cp*(Tout - Tin);

eps_r = 0.05599 + 1.039e-4*Tr + 2.249e-7*(Tr^2);
Tsky = 0.0553*(Tam^1.5);
hout = 4*(Vwind^0.58)*(ptc.Dco^(-0.42));

denom = (1/eps_r) + ((1 - ptc.eps_c)/ptc.eps_c)*(ptc.Aro/ptc.Aci);
QlossR2C = ptc.Aro*sigma*(Tr^4 - Tc^4)/denom;
QlossC2A = ptc.Aco*hout*(Tc - Tam) + ptc.Aco*sigma*ptc.eps_c*(Tc^4 - Tsky^4);
QuConv = h*ptc.Ari*(Tr - Tfm);

F = zeros(3,1);
F(1) = QlossR2C - QlossC2A;
F(2) = Qu - QuConv;
F(3) = Qabs - Qu - QlossR2C;
end

function value = localGet(S,fieldName,defaultValue)
if isfield(S,fieldName) && ~isempty(S.(fieldName))
    value = S.(fieldName);
else
    value = defaultValue;
end
end

function S = localSetDefault(S,fieldName,defaultValue)
if ~isfield(S,fieldName) || isempty(S.(fieldName))
    S.(fieldName) = defaultValue;
end
end
