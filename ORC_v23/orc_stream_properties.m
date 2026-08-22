function orcValue = orc_stream_properties(config,orcStream,varargin)
% ORC_STREAM_PROPERTIES Property interface for ORC-side external streams.
%
% Example:
%   h = orc_stream_properties(config,orcHotStream,'H','T',T,'P',P);
%
% Required stream field:
%   orcStream.fluid   CoolProp fluid name or local external-stream fluid [-]
%
% Optional stream field:
%   orcStream.property_backend   'coolprop' or a local external-stream backend [-]

% =========================================================================
% INPUT CHECK
% =========================================================================
if nargin < 3
    error('orc_stream_properties:NotEnoughInputs', ...
        'A stream and a property request are required.');
end
if ~isfield(orcStream,'fluid') || isempty(orcStream.fluid)
    error('orc_stream_properties:MissingFluid', ...
        'The ORC stream must define orcStream.fluid.');
end

config = orc_default_config(config);

if localIsSyltherm800(orcStream.fluid)
    orcValue = localSyltherm800Property(varargin{:});
    localCheckOutput(orcValue);
    return
end

% =========================================================================
% STREAM BACKEND
% =========================================================================
if isfield(orcStream,'property_backend') && ~isempty(orcStream.property_backend)
    orcBackend = lower(string(orcStream.property_backend));
else
    orcBackend = lower(string(config.orc_property_backend));
end

switch orcBackend
    case "coolprop"
        orcValue = orc_properties(config,varargin{:},orcStream.fluid);

    case "fluidgrid"
        orcValue = orc_properties(config,varargin{:},orcStream.fluid);

    otherwise
        error('orc_stream_properties:UnknownBackend', ...
            'Unknown external-stream property backend: %s',char(orcBackend));
end

% =========================================================================
% OUTPUT CHECK
% =========================================================================
localCheckOutput(orcValue);

end

function tf = localIsSyltherm800(fluid)
name = regexprep(lower(char(string(fluid))),'[^a-z0-9]','');
tf = any(strcmp(name,{'syltherm800','syltherm'}));
end

function value = localSyltherm800Property(varargin)
if numel(varargin) < 1
    error('orc_stream_properties:SylthermRequest','Missing Syltherm800 property request.');
end
outKey = upper(char(string(varargin{1})));
state = localParseState(varargin(2:end));

switch outKey
    case {'H','HMASS','ENTHALPY'}
        T = localRequireStateT(state,outKey);
        value = localSyltherm800Enthalpy(T);
    case {'T','TEMPERATURE'}
        if isfield(state,'T')
            value = state.T;
        elseif isfield(state,'H')
            value = localSyltherm800TemperatureFromH(state.H);
        else
            error('orc_stream_properties:SylthermTemperature', ...
                'Syltherm800 temperature request requires T or H in the state.');
        end
    case {'D','DMASS','RHO','DENSITY'}
        T = localRequireStateT(state,outKey);
        [rho,~,~,~] = localSyltherm800Props(T);
        value = rho;
    case {'C','CPMASS','CP','CP0MASS'}
        T = localRequireStateT(state,outKey);
        [~,cp,~,~] = localSyltherm800Props(T);
        value = cp;
    case {'V','VISCOSITY','MU'}
        T = localRequireStateT(state,outKey);
        [~,~,~,mu] = localSyltherm800Props(T);
        value = mu;
    case {'L','CONDUCTIVITY','THERMAL_CONDUCTIVITY'}
        T = localRequireStateT(state,outKey);
        [~,~,k,~] = localSyltherm800Props(T);
        value = k;
    otherwise
        error('orc_stream_properties:SylthermUnsupportedProperty', ...
            'Unsupported Syltherm800 property: %s',outKey);
end
end

function state = localParseState(args)
if mod(numel(args),2) ~= 0
    error('orc_stream_properties:SylthermStatePairs', ...
        'Syltherm800 state inputs must be key/value pairs.');
end
state = struct();
for i = 1:2:numel(args)
    key = upper(char(string(args{i})));
    val = args{i+1};
    if ~isnumeric(val) || ~isscalar(val)
        error('orc_stream_properties:SylthermStateValue', ...
            'Syltherm800 state value for %s must be numeric scalar.',key);
    end
    switch key
        case {'T','TEMPERATURE'}
            state.T = val;
        case {'H','HMASS','ENTHALPY'}
            state.H = val;
        case {'P','PRESSURE'}
            state.P = val;
        otherwise
            state.(matlab.lang.makeValidName(key)) = val;
    end
end
end

function T = localRequireStateT(state,outKey)
if isfield(state,'T')
    T = state.T;
elseif isfield(state,'H')
    T = localSyltherm800TemperatureFromH(state.H);
else
    error('orc_stream_properties:SylthermMissingTemperature', ...
        'Syltherm800 property %s requires T or H in the state.',outKey);
end
end

function h = localSyltherm800Enthalpy(TK)
Tref = 273.15;
Tgrid = linspace(min(Tref,TK),max(Tref,TK),80);
[~,cp,~,~] = localSyltherm800Props(Tgrid);
hAbs = trapz(Tgrid,cp);
if TK >= Tref
    h = hAbs;
else
    h = -hAbs;
end
end

function T = localSyltherm800TemperatureFromH(h)
Tref = 273.15;
Tlo = 233.15;
Thi = 673.15;
if h < localSyltherm800Enthalpy(Tlo)
    Tlo = 173.15;
end
if h > localSyltherm800Enthalpy(Thi)
    Thi = 873.15;
end
f = @(T) localSyltherm800Enthalpy(T) - h;
try
    T = fzero(f,[Tlo,Thi]);
catch
    cpRef = 1600;
    T = Tref + h/cpRef;
end
end

function [rho,cp,k,mu] = localSyltherm800Props(TK)
TC = TK - 273.15;
data = [ ...
    -40 1.506 990.61 0.1463 51.05
    -30 1.523 981.08 0.1444 35.45
    -20 1.540 971.68 0.1425 25.86
    -10 1.557 962.37 0.1407 19.61
      0 1.574 953.16 0.1388 15.33
     10 1.591 944.04 0.1369 12.27
     20 1.608 934.99 0.1350 10.03
     30 1.625 926.00 0.1331  8.32
     40 1.643 917.07 0.1312  7.00
     50 1.660 908.18 0.1294  5.96
     60 1.677 899.32 0.1275  5.12
     70 1.694 890.49 0.1256  4.43
     80 1.711 881.68 0.1237  3.86
     90 1.728 872.86 0.1218  3.39
    100 1.745 864.05 0.1200  2.99
    110 1.762 855.21 0.1181  2.65
    120 1.779 846.35 0.1162  2.36
    130 1.796 837.46 0.1143  2.11
    140 1.813 828.51 0.1124  1.89
    150 1.830 819.51 0.1106  1.70
    160 1.847 810.45 0.1087  1.54
    170 1.864 801.31 0.1068  1.39
    180 1.882 792.08 0.1049  1.26
    190 1.899 782.76 0.1030  1.15
    200 1.916 773.33 0.1012  1.05
    210 1.933 763.78 0.0993  0.96
    220 1.950 754.11 0.0974  0.88
    230 1.967 744.30 0.0955  0.81
    240 1.984 734.35 0.0936  0.74
    250 2.001 724.24 0.0918  0.69
    260 2.018 713.96 0.0899  0.63
    270 2.035 703.51 0.0880  0.59
    280 2.052 692.87 0.0861  0.54
    290 2.069 682.03 0.0842  0.50
    300 2.086 670.99 0.0824  0.47
    310 2.104 659.73 0.0805  0.44
    320 2.121 648.24 0.0786  0.41
    330 2.138 636.52 0.0767  0.38
    340 2.155 624.55 0.0748  0.36
    350 2.172 612.33 0.0729  0.33
    360 2.189 599.83 0.0711  0.31
    370 2.206 587.07 0.0692  0.29
    380 2.223 574.01 0.0673  0.28
    390 2.240 560.66 0.0654  0.26
    400 2.257 547.00 0.0635  0.25
];
T = data(:,1);
cp = interp1(T,data(:,2),TC,'linear','extrap')*1000;
rho = interp1(T,data(:,3),TC,'linear','extrap');
k = interp1(T,data(:,4),TC,'linear','extrap');
mu = interp1(T,data(:,5),TC,'linear','extrap')*1e-3;
rho = max(rho,1);
cp = max(cp,1);
k = max(k,1e-4);
mu = max(mu,1e-6);
end

function localCheckOutput(orcValue)
if isnumeric(orcValue) && any(~isfinite(orcValue(:)))
    error('orc_stream_properties:NonFiniteProperty', ...
        'The property backend returned a non-finite value.');
end
end
