function ReportFile = write_simulation_report_v1(cfg,Summary,Hourly,PHDesign,CTDesign,orcDesign,orcAnnual,ReportFile)
%WRITE_SIMULATION_REPORT_V1 Write a readable text report for one V1 run.

if nargin < 8 || isempty(ReportFile)
    ReportFile = fullfile(cfg.project_root,'Results','single_config_v1_report.txt');
end

reportDir = fileparts(ReportFile);
if ~isfolder(reportDir)
    mkdir(reportDir);
end

fid = fopen(ReportFile,'w');
if fid < 0
    error('write_simulation_report_v1:OpenFailed','Cannot open report file: %s',ReportFile);
end
cleanupObj = onCleanup(@() fclose(fid));

fprintf(fid,'Integrated Solar-ORC-RO System V1 Simulation Report\n');
fprintf(fid,'Generated: %s\n',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
fprintf(fid,'Project root: %s\n\n',cfg.project_root);

fprintf(fid,'RUN INPUTS\n');
fprintf(fid,'==========\n');
localPrintStruct(fid,cfg,'cfg',0);

fprintf(fid,'\nSUMMARY RESULTS\n');
fprintf(fid,'===============\n');
localPrintTableRow(fid,Summary);

fprintf(fid,'\nSTATUS COUNTS\n');
fprintf(fid,'=============\n');
localPrintStatusCounts(fid,Hourly,'system_status');
localPrintStatusCounts(fid,Hourly,'orc_status');
localPrintStatusCounts(fid,Hourly,'solar_flow_status');
localPrintStatusCounts(fid,Hourly,'solar_flow_search_status');
localPrintStatusCounts(fid,Hourly,'storage_status');
localPrintStatusCounts(fid,Hourly,'preheater_status');
localPrintStatusCounts(fid,Hourly,'ct_status');
localPrintStatusCounts(fid,Hourly,'ro_status');
localPrintStatusCounts(fid,Hourly,'orc_off_reason');

fprintf(fid,'\nRUNTIME PROFILE\n');
fprintf(fid,'===============\n');
localPrintRuntimeProfile(fid,Summary);

fprintf(fid,'\nKEY DESIGN RESULTS\n');
fprintf(fid,'==================\n');
localPrintPreheater(fid,PHDesign);
localPrintCoolingTower(fid,CTDesign);
localPrintOrc(fid,orcDesign,orcAnnual);

fprintf(fid,'\nOUTPUT FILES\n');
fprintf(fid,'============\n');
fprintf(fid,'hourly_csv  : %s\n',localGetNested(cfg,'outputs','hourly_csv',''));
fprintf(fid,'summary_csv : %s\n',localGetNested(cfg,'outputs','summary_csv',''));
fprintf(fid,'summary_mat : %s\n',localGetNested(cfg,'outputs','summary_mat',''));
fprintf(fid,'report_txt  : %s\n',ReportFile);
fprintf(fid,'run_dir     : %s\n',localGetNested(cfg,'outputs','run_dir',''));
fprintf(fid,'figures_dir : %s\n',localGetNested(cfg,'outputs','figures_dir',''));
end

function localPrintStruct(fid,S,prefix,indent)
fields = fieldnames(S);
pad = repmat(' ',1,indent);
for i = 1:numel(fields)
    name = fields{i};
    value = S.(name);
    key = [prefix '.' name];
    if isstruct(value) && isscalar(value)
        fprintf(fid,'%s%s\n',pad,key);
        localPrintStruct(fid,value,key,indent + 2);
    else
        fprintf(fid,'%s%s = %s\n',pad,key,localValueToText(value));
    end
end
end

function localPrintTableRow(fid,T)
if isempty(T)
    fprintf(fid,'No summary table was generated.\n');
    return
end
names = T.Properties.VariableNames;
for i = 1:numel(names)
    fprintf(fid,'%s = %s\n',names{i},localValueToText(T.(names{i})(1)));
end
end

function localPrintRuntimeProfile(fid,Summary)
names = Summary.Properties.VariableNames;
for i = 1:numel(names)
    name = names{i};
    if startsWith(name,'runtime_')
        fprintf(fid,'%s = %s\n',name,localValueToText(Summary.(name)(1)));
    end
end
end

function localPrintStatusCounts(fid,T,statusName)
if ~any(strcmp(T.Properties.VariableNames,statusName))
    return
end
status = string(T.(statusName));
values = unique(status);
fprintf(fid,'%s:\n',statusName);
for i = 1:numel(values)
    fprintf(fid,'  %-24s %d\n',char(values(i)),sum(status == values(i)));
end
end

function localPrintPreheater(fid,D)
fprintf(fid,'Preheater:\n');
localPrintField(fid,D,'status','  ');
localPrintField(fid,D,'method','  ');
localPrintField(fid,D,'Q_design_W','  ');
localPrintField(fid,D,'A_design_m2','  ');
localPrintField(fid,D,'UA_design_WK','  ');
localPrintField(fid,D,'U_design_Wm2K','  ');
localPrintField(fid,D,'N_parallel','  ');
localPrintField(fid,D,'Nt','  ');
localPrintField(fid,D,'Ltube_m','  ');
localPrintField(fid,D,'Dshell_m','  ');
localPrintField(fid,D,'T_cold_in_design_C','  ');
localPrintField(fid,D,'T_cold_out_design_C','  ');
localPrintField(fid,D,'T_cold_out_requested_C','  ');
localPrintField(fid,D,'T_hot_in_design_C','  ');
localPrintField(fid,D,'T_hot_out_design_C','  ');
end

function localPrintCoolingTower(fid,D)
fprintf(fid,'Cooling tower:\n');
localPrintField(fid,D,'Q_rated_W','  ');
localPrintField(fid,D,'T_w_in_rated_C','  ');
localPrintField(fid,D,'T_w_out_rated_C','  ');
localPrintField(fid,D,'mdot_water_rated','  ');
localPrintField(fid,D,'mdot_air_rated','  ');
localPrintField(fid,D,'W_fan_rated_W','  ');
end

function localPrintOrc(fid,orcDesign,orcAnnual)
fprintf(fid,'ORC:\n');
if isfield(orcDesign,'orc_thermo')
    T = orcDesign.orc_thermo;
    localPrintField(fid,T,'W_net','  design.');
    localPrintField(fid,T,'Q_orcevap','  design.');
    localPrintField(fid,T,'Q_orccond','  design.');
    localPrintField(fid,T,'P_orcevap','  design.');
    localPrintField(fid,T,'P_orccond','  design.');
    localPrintField(fid,T,'mdot_orc','  design.');
end
if isfield(orcAnnual,'orc_nStep')
    fprintf(fid,'  annual.orc_nStep = %s\n',localValueToText(orcAnnual.orc_nStep));
end
end

function localPrintField(fid,S,fieldName,prefix)
if isfield(S,fieldName)
    fprintf(fid,'%s%s = %s\n',prefix,fieldName,localValueToText(S.(fieldName)));
end
end

function txt = localValueToText(value)
if isnumeric(value)
    if isempty(value)
        txt = '[]';
    elseif isscalar(value)
        txt = sprintf('%.12g',value);
    else
        txt = mat2str(value,6);
    end
elseif islogical(value)
    if isscalar(value)
        txt = char(string(value));
    else
        txt = mat2str(value);
    end
elseif ischar(value)
    txt = value;
elseif isstring(value)
    txt = char(strjoin(value(:).',', '));
elseif iscell(value)
    try
        txt = char(strjoin(string(value(:).'),', '));
    catch
        txt = sprintf('<%dx%d cell>',size(value,1),size(value,2));
    end
elseif istable(value)
    txt = sprintf('<%dx%d table>',height(value),width(value));
elseif isstruct(value)
    txt = sprintf('<%dx%d struct>',size(value,1),size(value,2));
else
    txt = sprintf('<%s>',class(value));
end
end

function value = localGetNested(S,sectionName,fieldName,defaultValue)
if isfield(S,sectionName) && isstruct(S.(sectionName)) && ...
        isfield(S.(sectionName),fieldName) && ~isempty(S.(sectionName).(fieldName))
    value = S.(sectionName).(fieldName);
else
    value = defaultValue;
end
end
