function CTAir = ct_psychrometrics(CTAmbient, CTConfig)
% CT_PSYCHROMETRICS  Humid-air properties for cooling-tower calculations.
%
%   CTAir = ct_psychrometrics(CTAmbient, CTConfig)
%
% CTAmbient required fields
%   T_db_C      dry-bulb temperature [degC]
%   P_atm_Pa    atmospheric pressure [Pa]
%
% CTAmbient must contain at least one humidity descriptor
%   T_wb_C      wet-bulb temperature [degC]  (priority if present)
%   RH_pct      relative humidity [%]
%   RH          relative humidity as fraction 0..1
%
% CTConfig.psychrometrics.backend
%   'auto' | 'coolprop' | 'correlation'
%
% CTAir fields
%   T_db_C, T_wb_C, RH, RH_pct, P_atm_Pa
%   omega, h_Jkgda, h_kJkgda
%   v_m3kgda, rho_da_kgm3, rho_ma_kgm3
%   p_ws_Pa, omega_sat, h_sat_Jkgda, backend_used

if nargin < 2 || isempty(CTConfig)
    CTConfig = ct_default_config();
end

required = {'T_db_C','P_atm_Pa'};
for k = 1:numel(required)
    if ~isfield(CTAmbient,required{k})
        error('ct_psychrometrics:MissingField','Missing CTAmbient.%s',required{k});
    end
end

hasTwb = isfield(CTAmbient,'T_wb_C') && ~isempty(CTAmbient.T_wb_C);
hasRH  = isfield(CTAmbient,'RH') && ~isempty(CTAmbient.RH);
hasRHp = isfield(CTAmbient,'RH_pct') && ~isempty(CTAmbient.RH_pct);

% WeatherData commonly contains both T_wb_C and RH_pct. For cooling-tower
% thermal calculations, wet-bulb temperature is the preferred humidity
% descriptor because the tower approach/limit is wet-bulb based. Therefore,
% if multiple humidity descriptors are supplied, use this priority:
%   T_wb_C > RH_pct > RH
% rather than throwing an error.
if ~(hasTwb || hasRH || hasRHp)
    error('ct_psychrometrics:HumidityInput', ...
        'CTAmbient must contain at least one of T_wb_C, RH_pct, or RH.');
end

if hasTwb
    CTHumidityInputUsed = 'T_wb_C';
    hasRH = false;
    hasRHp = false;
elseif hasRHp
    CTHumidityInputUsed = 'RH_pct';
    hasRH = false;
else
    CTHumidityInputUsed = 'RH';
end

backend = char(CTConfig.psychrometrics.backend);
if ~(strcmpi(backend,'auto') || strcmpi(backend,'coolprop') || strcmpi(backend,'correlation'))
    error('ct_psychrometrics:Backend','Unknown CTConfig psychrometric backend: %s',backend);
end

T_db_C = CTAmbient.T_db_C;
P_atm_Pa = CTAmbient.P_atm_Pa;
if hasRHp
    RH_in = CTAmbient.RH_pct ./ 100;
elseif hasRH
    RH_in = CTAmbient.RH;
else
    RH_in = [];
end
if hasTwb, Twb_in = CTAmbient.T_wb_C; else, Twb_in = []; end

inputs = {T_db_C, P_atm_Pa};
if ~isempty(Twb_in), inputs{end+1} = Twb_in; end %#ok<AGROW>
if ~isempty(RH_in),  inputs{end+1} = RH_in;  end %#ok<AGROW>
N = max(cellfun(@numel, inputs));
for k = 1:numel(inputs)
    if numel(inputs{k}) ~= 1 && numel(inputs{k}) ~= N
        error('ct_psychrometrics:SizeMismatch', ...
            'All nonscalar CTAmbient fields must have the same number of elements.');
    end
end

sz = size(T_db_C);
if numel(T_db_C) == 1
    for k = 1:numel(inputs)
        if numel(inputs{k}) == N && N > 1
            sz = size(inputs{k});
            break
        end
    end
end

Tdb = expand_to_N(T_db_C,N);
P   = expand_to_N(P_atm_Pa,N);
if ~isempty(Twb_in), TwbKnown = expand_to_N(Twb_in,N); else, TwbKnown = nan(N,1); end
if ~isempty(RH_in),  RHKnown  = expand_to_N(RH_in,N);  else, RHKnown  = nan(N,1); end

omega = nan(N,1); h = nan(N,1); Twb = nan(N,1); RH = nan(N,1);
pws_db = nan(N,1); omega_sat = nan(N,1); h_sat = nan(N,1);
backend_used = cell(N,1);

for i = 1:N
    validate_state(Tdb(i),P(i));
    useCP = strcmpi(backend,'coolprop') || strcmpi(backend,'auto');
    cpSuccess = false;

    if useCP
        try
            if ~isnan(TwbKnown(i))
                TdbK = Tdb(i)+273.15; TwbK = TwbKnown(i)+273.15;
                omega(i) = scalarize(HAPropsSI('W','T',TdbK,'P',P(i),'Twb',TwbK));
                h(i)     = scalarize(HAPropsSI('H','T',TdbK,'P',P(i),'Twb',TwbK));
                RH(i)    = scalarize(HAPropsSI('R','T',TdbK,'P',P(i),'W',omega(i)));
                Twb(i)   = TwbKnown(i);
            else
                TdbK = Tdb(i)+273.15;
                RH_i = min(max(RHKnown(i),0),1);
                omega(i) = scalarize(HAPropsSI('W','T',TdbK,'P',P(i),'R',RH_i));
                h(i)     = scalarize(HAPropsSI('H','T',TdbK,'P',P(i),'R',RH_i));
                TwbK     = scalarize(HAPropsSI('Twb','T',TdbK,'P',P(i),'R',RH_i));
                Twb(i)   = TwbK-273.15;
                RH(i)    = RH_i;
            end
            omega_sat(i) = scalarize(HAPropsSI('W','T',Tdb(i)+273.15,'P',P(i),'R',1.0));
            h_sat(i)     = scalarize(HAPropsSI('H','T',Tdb(i)+273.15,'P',P(i),'R',1.0));
            pws_db(i)    = omega_sat(i)*P(i)/(0.62198+omega_sat(i));
            backend_used{i} = 'coolprop';
            cpSuccess = all(isfinite([omega(i),h(i),Twb(i),RH(i),omega_sat(i),h_sat(i)]));
        catch ME
            if strcmpi(backend,'coolprop'), rethrow(ME); end
            cpSuccess = false;
        end
    end

    if ~cpSuccess
        if ~isnan(TwbKnown(i))
            [omega(i),h(i),RH(i)] = psychro_from_db_wb_corr(Tdb(i),TwbKnown(i),P(i));
            Twb(i) = TwbKnown(i);
        else
            RH(i) = min(max(RHKnown(i),0),1);
            [omega(i),h(i)] = psychro_from_db_rh_corr(Tdb(i),RH(i),P(i));
            Twb(i) = wetbulb_stull(Tdb(i),100*RH(i));
        end
        pws_db(i) = buck_psat(Tdb(i));
        omega_sat(i) = 0.62198*pws_db(i)/max(P(i)-pws_db(i),1e-9);
        h_sat(i) = moist_air_enthalpy_corr(Tdb(i),omega_sat(i));
        backend_used{i} = 'correlation';
    end
end

R_da = 287.055;
v = R_da.*(Tdb+273.15)./P.*(1+1.607858.*omega);
rho_da = 1./v;
rho_ma = (1+omega)./v;

CTAir = struct();
CTAir.T_db_C = reshape(Tdb,sz);
CTAir.T_wb_C = reshape(Twb,sz);
CTAir.RH = reshape(RH,sz);
CTAir.RH_pct = reshape(100*RH,sz);
CTAir.P_atm_Pa = reshape(P,sz);
CTAir.omega = reshape(omega,sz);
CTAir.h_Jkgda = reshape(h,sz);
CTAir.h_kJkgda = reshape(h/1000,sz);
CTAir.v_m3kgda = reshape(v,sz);
CTAir.rho_da_kgm3 = reshape(rho_da,sz);
CTAir.rho_ma_kgm3 = reshape(rho_ma,sz);
CTAir.p_ws_Pa = reshape(pws_db,sz);
CTAir.omega_sat = reshape(omega_sat,sz);
CTAir.h_sat_Jkgda = reshape(h_sat,sz);
CTAir.backend_used = reshape(backend_used,sz);
CTAir.humidity_input_used = CTHumidityInputUsed;
end

function x = expand_to_N(x,N)
if isscalar(x), x = repmat(double(x),N,1); else, x = double(x(:)); end
end
function validate_state(T,P)
if ~isfinite(T) || T < -80 || T > 100
    error('ct_psychrometrics:Temperature','Invalid CTAmbient.T_db_C: %.6g C',T);
end
if ~isfinite(P) || P < 5e4 || P > 1.2e5
    error('ct_psychrometrics:Pressure','Invalid CTAmbient.P_atm_Pa: %.6g Pa',P);
end
end
function y = scalarize(x), y = double(x); y = y(1); end
function [omega,h,RH] = psychro_from_db_wb_corr(Tdb,Twb,P)
pws_wb = buck_psat(Twb); A = 0.00066*(1+0.00115*Twb)*P;
pv = pws_wb-A*(Tdb-Twb); pws_db = buck_psat(Tdb);
pv = max(1.0,min(pv,0.999*pws_db));
omega = 0.62198*pv/max(P-pv,1e-9); h = moist_air_enthalpy_corr(Tdb,omega);
RH = min(max(pv/max(pws_db,1e-9),0),1);
end
function [omega,h] = psychro_from_db_rh_corr(Tdb,RH,P)
pv = RH*buck_psat(Tdb); omega = 0.62198*pv/max(P-pv,1e-9);
h = moist_air_enthalpy_corr(Tdb,omega);
end
function h = moist_air_enthalpy_corr(Tdb,omega)
h = 1006*Tdb + omega*(2501000+1860*Tdb);
end
function pws = buck_psat(T)
pws = 611.21.*exp((18.678-T./234.5).*(T./(257.14+T)));
end
function Twb_C = wetbulb_stull(T_C,RH_pct)
RH = RH_pct;
Twb_C = T_C.*atan(0.151977.*sqrt(RH+8.313659)) + atan(T_C+RH) ...
    - atan(RH-1.676331) + 0.00391838.*(RH.^(3/2)).*atan(0.023101.*RH) - 4.686035;
end
