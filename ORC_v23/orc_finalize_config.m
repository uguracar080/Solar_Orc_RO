function config = orc_finalize_config(config)
%ORC_FINALIZE_CONFIG Apply ORC defaults once and mark config immutable.
%
% Low-level ORC functions still accept partial configs. Passing a finalized
% config skips repeated default filling in hot property and rating paths.

if nargin < 1 || isempty(config)
    config = struct();
end
config = orc_default_config(config);
config.orc_config_finalized = true;
end
