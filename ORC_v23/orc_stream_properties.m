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
    case {'STATE','BUNDLE','PROPS'}
        value = localSyltherm800StateBundle(state);
    case {'H','HMASS','ENTHALPY'}
        T = localRequireStateT(state,outKey);
        value = syltherm800_properties_v2('H',T);
    case {'T','TEMPERATURE'}
        if isfield(state,'T')
            value = state.T;
        elseif isfield(state,'H')
            value = syltherm800_properties_v2('T_FROM_H',state.H);
        else
            error('orc_stream_properties:SylthermTemperature', ...
                'Syltherm800 temperature request requires T or H in the state.');
        end
    case {'D','DMASS','RHO','DENSITY'}
        T = localRequireStateT(state,outKey);
        [rho,~,~,~] = syltherm800_properties_v2(T);
        value = rho;
    case {'C','CPMASS','CP','CP0MASS'}
        T = localRequireStateT(state,outKey);
        [~,cp,~,~] = syltherm800_properties_v2(T);
        value = cp;
    case {'V','VISCOSITY','MU'}
        T = localRequireStateT(state,outKey);
        [~,~,~,mu] = syltherm800_properties_v2(T);
        value = mu;
    case {'L','CONDUCTIVITY','THERMAL_CONDUCTIVITY'}
        T = localRequireStateT(state,outKey);
        [~,~,k,~] = syltherm800_properties_v2(T);
        value = k;
    otherwise
        error('orc_stream_properties:SylthermUnsupportedProperty', ...
            'Unsupported Syltherm800 property: %s',outKey);
end
end

function props = localSyltherm800StateBundle(state)
if isfield(state,'T')
    T = state.T;
    h = syltherm800_properties_v2('H',T);
elseif isfield(state,'H')
    h = state.H;
    T = syltherm800_properties_v2('T_FROM_H',h);
else
    error('orc_stream_properties:SylthermMissingTemperature', ...
        'Syltherm800 STATE request requires T or H in the state.');
end
[rho,cp,k,mu] = syltherm800_properties_v2(T);
props = struct();
props.T = T;
props.h = h;
props.rho = rho;
props.cp = cp;
props.k = k;
props.mu = mu;
props.Q = NaN;
if isfield(state,'P')
    props.P = state.P;
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
    T = syltherm800_properties_v2('T_FROM_H',state.H);
else
    error('orc_stream_properties:SylthermMissingTemperature', ...
        'Syltherm800 property %s requires T or H in the state.',outKey);
end
end

function localCheckOutput(orcValue)
if isnumeric(orcValue) && any(~isfinite(orcValue(:)))
    error('orc_stream_properties:NonFiniteProperty', ...
        'The property backend returned a non-finite value.');
end
end
