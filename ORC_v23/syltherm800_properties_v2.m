function varargout = syltherm800_properties_v2(varargin)
%SYLTHERM800_PROPERTIES_V2 Cached Syltherm 800 property table.
%
% Default call:
%   [rho,cp,k,mu] = syltherm800_properties_v2(T_K)
%
% Request calls:
%   h_Jkg  = syltherm800_properties_v2('H',T_K)
%   T_K    = syltherm800_properties_v2('T_FROM_H',h_Jkg)

if nargin < 1
    error('syltherm800_properties_v2:NotEnoughInputs', ...
        'A temperature or property request is required.');
end

if isnumeric(varargin{1})
    [rho,cp,k,mu] = localPropsFromT(varargin{1});
    varargout = localPackOutputs(nargout,rho,cp,k,mu);
    return
end

request = upper(char(string(varargin{1})));
if nargin < 2
    error('syltherm800_properties_v2:MissingState', ...
        'Request %s requires a numeric state value.',request);
end

switch request
    case {'PROPS','PROPERTIES'}
        [rho,cp,k,mu] = localPropsFromT(varargin{2});
        varargout = localPackOutputs(nargout,rho,cp,k,mu);

    case {'H','HMASS','ENTHALPY'}
        cache = localCache();
        varargout{1} = cache.hFromT(varargin{2});

    case {'T','T_FROM_H','TEMPERATURE_FROM_H'}
        cache = localCache();
        varargout{1} = cache.tFromH(varargin{2});

    case {'CP','C','CPMASS','CP0MASS'}
        [~,cp,~,~] = localPropsFromT(varargin{2});
        varargout{1} = cp;

    case {'RHO','D','DMASS','DENSITY'}
        [rho,~,~,~] = localPropsFromT(varargin{2});
        varargout{1} = rho;

    case {'MU','V','VISCOSITY'}
        [~,~,~,mu] = localPropsFromT(varargin{2});
        varargout{1} = mu;

    case {'K','L','CONDUCTIVITY','THERMAL_CONDUCTIVITY'}
        [~,~,k,~] = localPropsFromT(varargin{2});
        varargout{1} = k;

    otherwise
        error('syltherm800_properties_v2:UnsupportedRequest', ...
            'Unsupported Syltherm800 property request: %s',request);
end
end

function outputs = localPackOutputs(nOut,rho,cp,k,mu)
if nOut <= 1
    outputs = {struct('rho',rho,'cp',cp,'k',k,'mu',mu)};
else
    values = {rho,cp,k,mu};
    if nOut > numel(values)
        error('syltherm800_properties_v2:TooManyOutputs', ...
            'At most four property outputs are available: rho, cp, k, mu.');
    end
    outputs = cell(1,nOut);
    for i = 1:nOut
        outputs{i} = values{i};
    end
end
end

function [rho,cp,k,mu] = localPropsFromT(TK)
cache = localCache();
rho = max(cache.rhoFromT(TK),1);
cp = max(cache.cpFromT(TK),1);
k = max(cache.kFromT(TK),1e-4);
mu = max(cache.muFromT(TK),1e-6);
end

function cache = localCache()
persistent C
if ~isempty(C)
    cache = C;
    return
end

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
    320 2.121 648.24 0.0786 0.41
    330 2.138 636.52 0.0767 0.38
    340 2.155 624.55 0.0748 0.36
    350 2.172 612.33 0.0729 0.33
    360 2.189 599.83 0.0711 0.31
    370 2.206 587.07 0.0692 0.29
    380 2.223 574.01 0.0673 0.28
    390 2.240 560.66 0.0654 0.26
    400 2.257 547.00 0.0635 0.25
];

Tdata_K = data(:,1) + 273.15;
cpData = data(:,2)*1000;
rhoData = data(:,3);
kData = data(:,4);
muData = data(:,5)*1e-3;

C.rhoFromT = griddedInterpolant(Tdata_K,rhoData,'linear','linear');
C.cpFromT = griddedInterpolant(Tdata_K,cpData,'linear','linear');
C.kFromT = griddedInterpolant(Tdata_K,kData,'linear','linear');
C.muFromT = griddedInterpolant(Tdata_K,muData,'linear','linear');

Tref_K = 273.15;
Tgrid_K = unique([173.15:0.25:1200.15, Tdata_K.', Tref_K]);
cpGrid = max(C.cpFromT(Tgrid_K),1);
hGrid = cumtrapz(Tgrid_K,cpGrid);
hGrid = hGrid - interp1(Tgrid_K,hGrid,Tref_K,'linear','extrap');

C.hFromT = griddedInterpolant(Tgrid_K,hGrid,'linear','linear');
C.tFromH = griddedInterpolant(hGrid,Tgrid_K,'linear','linear');

cache = C;
end
