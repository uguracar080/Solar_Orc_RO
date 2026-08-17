function orcValue = orc_properties(config,varargin)
% ORC_PROPERTIES Central property interface for all ORC working-fluid files.
%
% CoolProp usage mirrors PropsSI:
%   h  = orc_properties(config,'H','P',P,'Q',0,fluid);
%   Pc = orc_properties(config,'PCRIT',fluid);
%
% R1233zd(E) thermal conductivity is supplied by the NIST correlation when
% CoolProp has no conductivity model for the installed fluid backend.

% =========================================================================
% INPUT CHECK
% =========================================================================
if nargin < 2
    error('orc_properties:NotEnoughInputs','Property request is missing.');
end

if ~isfield(config,'orc_property_backend')
    config = orc_default_config(config);
else
    config = orc_default_config(config);
end

% =========================================================================
% PROPERTY CACHE AND DIAGNOSTIC COMMANDS
% =========================================================================
persistent orcPropertyCache orcPropertyStats
if isempty(orcPropertyCache)
    orcPropertyCache = containers.Map('KeyType','char','ValueType','any');
end
if isempty(orcPropertyStats)
    orcPropertyStats = localBlankCacheStats();
end

% Utility commands used by quickstart/test suites.  They are intentionally
% handled here so the cache remains private to this property interface.
if numel(varargin) >= 1 && (ischar(varargin{1}) || isstring(varargin{1}))
    orcCacheCommand = upper(string(varargin{1}));       % [-]
    if orcCacheCommand == "CACHESTATS"
        orcValue = localGetCacheStats(orcPropertyCache,orcPropertyStats); % [-]
        return
    elseif orcCacheCommand == "CACHERESET"
        orcPropertyCache = containers.Map('KeyType','char','ValueType','any');
        orcPropertyStats = localBlankCacheStats();
        orcValue = true;                               % reset acknowledged [-]
        return
    end
end

orcUseCache = isfield(config,'orc_property_cache_enabled') && ...
    logical(config.orc_property_cache_enabled);        % [-]
orcUseStats = isfield(config,'orc_property_cache_stats_enabled') && ...
    logical(config.orc_property_cache_stats_enabled);  % [-]
orcCacheKey = '';                                      % [-]

if orcUseStats
    orcPropertyStats.nRequests = orcPropertyStats.nRequests + 1; % [-]
end

if orcUseCache
    orcCacheKey = localBuildCacheKey(varargin{:});     % [-]
    if isKey(orcPropertyCache,orcCacheKey)
        if orcUseStats
            orcPropertyStats.nHits = orcPropertyStats.nHits + 1; % [-]
        end
        orcValue = orcPropertyCache(orcCacheKey);      % cached value [-]
        return
    else
        if orcUseStats
            orcPropertyStats.nMisses = orcPropertyStats.nMisses + 1; % [-]
        end
    end
else
    if orcUseStats
        orcPropertyStats.nBypass = orcPropertyStats.nBypass + 1; % [-]
    end
end

% =========================================================================
% PROPERTY BACKEND
% =========================================================================
orcBackend = lower(string(config.orc_property_backend));

switch orcBackend
    case "coolprop"
        if exist('PropsSI','file') ~= 2
            error('orc_properties:PropsSIMissing', ...
                ['PropsSI.m is not on the MATLAB path. Add the supplied ', ...
                 'PropsSI wrapper and configure Python CoolProp first.']);
        end

        % Use source-based k model before CoolProp for R1233zd(E). [W/m/K]
        if localIsR1233zdEConductivityRequest(config,varargin{:})
            orcValue = localR1233zdEConductivityFromState(config,varargin{:});
        else
            try
                orcValue = PropsSI(varargin{:});
            catch orcME
                if localCanFallbackToR1233zdEConductivity(config,varargin{:})
                    orcValue = localR1233zdEConductivityFromState(config,varargin{:});
                else
                    rethrow(orcME);
                end
            end
        end

    case "fluidgrid"
        error('orc_properties:FluidGridNotImplemented', ...
            ['Fluid-grid backend is intentionally disabled in ORC v0.7. ', ...
             'The interface is reserved for the later acceleration stage.']);

    otherwise
        error('orc_properties:UnknownBackend', ...
            'Unknown ORC property backend: %s',char(orcBackend));
end

% =========================================================================
% OUTPUT CHECK
% =========================================================================
if isnumeric(orcValue) && any(~isfinite(orcValue(:)))
    error('orc_properties:NonFiniteProperty', ...
        'The property backend returned a non-finite value.');
end

% =========================================================================
% CACHE STORE
% =========================================================================
if orcUseCache
    if isfield(config,'orc_property_cache_maxEntries') && ...
            orcPropertyCache.Count > config.orc_property_cache_maxEntries
        orcPropertyCache = containers.Map('KeyType','char','ValueType','any');
        if orcUseStats
            orcPropertyStats.nResets = orcPropertyStats.nResets + 1; % [-]
        end
    end
    orcPropertyCache(orcCacheKey) = orcValue;          % store value [-]
    if orcUseStats
        orcPropertyStats.nStores = orcPropertyStats.nStores + 1; % [-]
    end
end

end

% =========================================================================
% LOCAL HELPER: CACHE KEY
% =========================================================================
function key = localBuildCacheKey(varargin)
% Build a compact cache key from a PropsSI-style request.
parts = cell(1,numel(varargin));
for i = 1:numel(varargin)
    v = varargin{i};
    if isnumeric(v)
        parts{i} = sprintf('%.12g,',v(:));             % numeric key [-]
    elseif isstring(v) || ischar(v)
        parts{i} = char(v);                            % text key [-]
    else
        parts{i} = class(v);                           % fallback key [-]
    end
end
key = strjoin(parts,'|');                              % [-]
end

% =========================================================================
% LOCAL HELPER: CACHE STATS
% =========================================================================
function st = localBlankCacheStats()
% Initialize property-cache diagnostic counters.
st = struct();
st.nRequests = 0;                                      % property requests [-]
st.nHits = 0;                                          % cache hits [-]
st.nMisses = 0;                                        % cache misses [-]
st.nStores = 0;                                        % stored values [-]
st.nBypass = 0;                                        % uncached requests [-]
st.nResets = 0;                                        % automatic cache clears [-]
end

function st = localGetCacheStats(cache,rawStats)
% Return counters plus derived cache metrics.
st = rawStats;                                        % copy counters [-]
st.nEntries = cache.Count;                            % current cache entries [-]
if st.nRequests > 0
    st.hitRate = st.nHits/st.nRequests;                % [-]
else
    st.hitRate = NaN;                                  % [-]
end
if (st.nHits + st.nMisses) > 0
    st.activeHitRate = st.nHits/(st.nHits + st.nMisses); % cache-only hit rate [-]
else
    st.activeHitRate = NaN;                            % [-]
end
end

% =========================================================================
% LOCAL HELPER: REQUEST TYPE
% =========================================================================
function tf = localIsR1233zdEConductivityRequest(config,varargin)
% Return true when NIST R1233zd(E) conductivity should be used.
tf = false;
if nargin < 2 || numel(varargin) < 2
    return
end
if ~isfield(config,'orc_r1233zde_k_useNist') || ~config.orc_r1233zde_k_useNist
    return
end
orcOutKey = upper(string(varargin{1}));
orcFluid = varargin{end};
if localIsConductivityKey(orcOutKey) && localIsR1233zdEFluid(orcFluid)
    tf = true;
end
end

% =========================================================================
% LOCAL HELPER: FALLBACK TYPE
% =========================================================================
function tf = localCanFallbackToR1233zdEConductivity(config,varargin)
% Return true when a failed CoolProp call can be replaced by NIST k.
tf = localIsR1233zdEConductivityRequest(config,varargin{:});
end

% =========================================================================
% LOCAL HELPER: CONDUCTIVITY KEY
% =========================================================================
function tf = localIsConductivityKey(orcOutKey)
% CoolProp commonly uses 'L' for thermal conductivity.
orcKey = upper(string(orcOutKey));
tf = any(orcKey == ["L","CONDUCTIVITY","THERMAL_CONDUCTIVITY"]);
end

% =========================================================================
% LOCAL HELPER: FLUID NAME
% =========================================================================
function tf = localIsR1233zdEFluid(orcFluid)
% Accept common R1233zd(E) string variants.
orcFluidClean = lower(regexprep(char(orcFluid),'[^a-zA-Z0-9]',''));
tf = contains(orcFluidClean,'r1233zde');
end

% =========================================================================
% LOCAL HELPER: NIST CONDUCTIVITY FROM PROPSI-STYLE STATE
% =========================================================================
function orcK = localR1233zdEConductivityFromState(config,varargin)
% Convert a PropsSI-style state request to T and rho, then evaluate k.

orcFluid = varargin{end};
orcN = numel(varargin);

if orcN < 6
    error('orc_properties:R1233zdEStateMissing', ...
        'R1233zd(E) conductivity requires two independent state inputs.');
end

orcKey1 = upper(string(varargin{2}));
orcVal1 = varargin{3};
orcKey2 = upper(string(varargin{4}));
orcVal2 = varargin{5};

% -------------------------------------------------------------------------
% Direct state if already available.
% -------------------------------------------------------------------------
orcHasT = false;
orcHasD = false;

if orcKey1 == "T"
    orcT = orcVal1;                                  % [K]
    orcHasT = true;
elseif any(orcKey1 == ["D","DMASS"])
    orcRho = orcVal1;                                % [kg/m3]
    orcHasD = true;
end

if orcKey2 == "T"
    orcT = orcVal2;                                  % [K]
    orcHasT = true;
elseif any(orcKey2 == ["D","DMASS"])
    orcRho = orcVal2;                                % [kg/m3]
    orcHasD = true;
end

% -------------------------------------------------------------------------
% Ask CoolProp only for thermodynamic T/rho, not conductivity.
% -------------------------------------------------------------------------
if ~orcHasT
    orcT = orc_properties(config,'T',char(orcKey1),orcVal1,char(orcKey2),orcVal2,orcFluid); % [K]
end
if ~orcHasD
    orcRho = orc_properties(config,'D',char(orcKey1),orcVal1,char(orcKey2),orcVal2,orcFluid); % [kg/m3]
end

% -------------------------------------------------------------------------
% Evaluate the source-based thermal conductivity.
% -------------------------------------------------------------------------
orcK = orc_r1233zde_thermal_conductivity(config,orcT,orcRho); % [W/m/K]
end
