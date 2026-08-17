function props = HAPropsSI(varargin)
% HAPropsSI - MATLAB wrapper for CoolProp.HumidAirProp.HAPropsSI
%
% PURPOSE:
% Provides vectorized access to CoolProp humid air properties
% similar in philosophy to PropsSI.m
%
% SUPPORTED INPUT FORMAT:
% HAPropsSI(output, input1_name, input1_values,
%                      input2_name, input2_values,
%                      input3_name, input3_values)
%
% Example:
% Twb = HAPropsSI('T_wb','T',300,'R',0.6,'P',101325);
%
% Author: Uğur Acar Style
% -----------------------------------------------------------

%% ================= INPUT VALIDATION =====================

if nargin ~= 7
    error('HAPropsSI requires 7 inputs.');
end

outputName = varargin{1};
in1_name   = varargin{2};
in1_val    = varargin{3};
in2_name   = varargin{4};
in2_val    = varargin{5};
in3_name   = varargin{6};
in3_val    = varargin{7};

% Basic checks
assert(ischar(outputName));
assert(ischar(in1_name));
assert(ischar(in2_name));
assert(ischar(in3_name));

validateattributes(in1_val, {'numeric'},{'vector'});
validateattributes(in2_val, {'numeric'},{'vector'});
validateattributes(in3_val, {'numeric'},{'vector'});

%% ================= MESHGRID (vectorization) =============

[XX,YY,ZZ] = ndgrid(in1_val, in2_val, in3_val);

%% ================= PYTHON IMPORT =========================

py.importlib.import_module('CoolProp.HumidAirProp');

%% ================= CALL HAPropsSI ========================

% Flatten arrays for Python call
Xflat = py.numpy.ravel(XX(:).');
Yflat = py.numpy.ravel(YY(:).');
Zflat = py.numpy.ravel(ZZ(:).');

% Python call
result = py.CoolProp.HumidAirProp.HAPropsSI( ...
          outputName, ...
          in1_name, Xflat, ...
          in2_name, Yflat, ...
          in3_name, Zflat);

%% ================= CONVERT BACK TO MATLAB ================

props = reshape(localPyNumericToVector(result), size(XX));

end

function values = localPyNumericToVector(pyValue)
% Convert a Python scalar/list/numpy array to a MATLAB double row vector.
if isnumeric(pyValue)
    values = double(pyValue);
    return
end
if isa(pyValue,'py.numpy.ndarray')
    pyValue = pyValue.ravel().tolist();
end
if isa(pyValue,'py.list') || isa(pyValue,'py.tuple')
    c = cell(pyValue);
    values = [];
    for k = 1:numel(c)
        values = [values localPyNumericToVector(c{k})]; %#ok<AGROW>
    end
else
    values = double(pyValue);
end
end
