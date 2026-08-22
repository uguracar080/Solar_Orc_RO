function thermoDB = water_grid_generator_V1(opts)
% WATER_GRID_GENERATOR_V1 Generate a V5-schema water property database.
%
% This wrapper uses grid_generator_V5 with water-focused default ranges.
% The (P,T) table is included because condenser, cooling-tower and reheater
% water streams usually request properties from temperature and pressure.

if nargin < 1 || isempty(opts)
    opts = struct();
end

opts = localSetDefault(opts,'fluid','Water');
opts = localSetDefault(opts,'Pmin_bar',1.8);
opts = localSetDefault(opts,'Pmax_bar',2.2);
opts = localSetDefault(opts,'Tmin_K',273.15);
opts = localSetDefault(opts,'Tmax_K',373.15);
opts = localSetDefault(opts,'hmin',0);
opts = localSetDefault(opts,'hmax',500e3);
opts = localSetDefault(opts,'smin',0);
opts = localSetDefault(opts,'smax',1800);
opts = localSetDefault(opts,'Np',11);
opts = localSetDefault(opts,'Ns',1000);
opts = localSetDefault(opts,'Nh',1000);
opts = localSetDefault(opts,'Nt',1000);
opts = localSetDefault(opts,'Nsat',1000);
opts = localSetDefault(opts,'fileSuffix','V5');

thermoDB = grid_generator_V5(opts);

end

function opts = localSetDefault(opts,fieldName,defaultValue)
if ~isfield(opts,fieldName) || isempty(opts.(fieldName))
    opts.(fieldName) = defaultValue;
end
end
