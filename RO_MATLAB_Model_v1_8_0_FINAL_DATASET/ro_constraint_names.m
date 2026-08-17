function names = ro_constraint_names() % ANN dataset icin uygulanan dimensionless inequality constraint isimlerini sirali olarak dondurur.

names = { ...
    'Stage1_feed_per_PV_max'; ... % Stage-1 feed flow/PV <= 16 m3/h.
    'Stage2_feed_per_PV_max'; ... % Stage-2 feed flow/PV <= 16 m3/h.
    'Stage1_brine_per_PV_min'; ... % Stage-1 brine flow/PV >= 3.6 m3/h.
    'Stage2_brine_per_PV_min'; ... % Stage-2 brine flow/PV >= 3.6 m3/h.
    'System_average_flux_max'; ... % System-average permeate flux <= 20 LMH.
    'Stage1_first_element_flux_max'; ... % Stage-1 first-element average flux <= 35 LMH.
    'Stage2_first_element_flux_max'; ... % Stage-2 first-element average flux <= 48 LMH.
    'Stage1_CPF_max'; ... % Stage-1 CPFmax <= 1.2.
    'Stage2_CPF_max'; ... % Stage-2 CPFmax <= 1.4.
    'Stage1_dP_max'; ... % Stage-1 pressure drop/PV <= 0.35 MPa.
    'Stage2_dP_max'; ... % Stage-2 pressure drop/PV <= 0.35 MPa.
    'Product_salinity_max'; ... % Product salinity <= 0.500 kg/m3.
    'Bulk_brine_concentration_max'; ... % Maximum feed-channel bulk concentration <= 90 kg/m3.
    'Stage1_pressure_max'; ... % Stage-1 operating pressure <= 8.3 MPa(g).
    'Stage2_pressure_max'; ... % Stage-2 operating pressure <= 8.3 MPa(g).
    'Temperature_max'; ... % RO membrane inlet temperature <= 45 C.
    'Interstage_booster_nonnegative_head'; ... % P2 must not be lower than Stage-1 outlet pressure.
    'PX_network_convergence'; ... % Coupled membrane-PX fixed-point solver must converge.
    'Stage1_local_convergence'; ... % Every Stage-1 axial local transport solve must converge.
    'Stage2_local_convergence'; ... % Every Stage-2 axial local transport solve must converge.
    'Stage1_no_flow_clipping'; ... % Stage-1 numerical 95% flow clip must remain inactive.
    'Stage2_no_flow_clipping'}; % Stage-2 numerical 95% flow clip must remain inactive.

end % Constraint-name fonksiyonunu sonlandirir.
