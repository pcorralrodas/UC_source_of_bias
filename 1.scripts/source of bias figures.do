set more off
clear all
if (lower("`c(username)'")=="wb378870") global main    "C:\Users\WB378870\GitHub\UC_source_of_bias\"
else global main "C:\Users\Paul Corral\Documents\GitHub\UC_source_of_bias\"
global mdata    "$main\0.data" 
global dboard "$main\4.other"


set processors 4

use "$mdata\source_of_bias_in_mymodel.dta", clear

// collapse to area level
groupfunction, mean(eb_* uc_* true_* mean_Y variance_XB var_Y e_y) by(area)

forval z=1/99{
	gen bias_uc_`z' = true_`z' - uc_fgt0_`z'
	gen bias_eb_`z' = true_`z' - eb_fgt0_`z'
	gen abs_bias_uc_`z' = abs(bias_uc_`z')
		lab var abs_bias_uc_`z' "Absolute bias for UC model (thold `z'%)"
	gen abs_bias_eb_`z' = abs(bias_eb_`z')
		lab var abs_bias_eb_`z' "Absolute bias for EB model (thold `z'%)"
}

gen bias_eb_W = e_y - eb_e_y
gen bias_uc_W = e_y - uc_e_y

gen abs_bias_eb_W = abs(e_y - eb_e_y)
gen abs_bias_uc_W = abs(e_y - uc_e_y)

drop eb_fgt0* uc_fgt0* true_*


egen double tot_var_eb = rsum(eb_var_eta eb_var_xb eb_eps)
egen double tot_var_uc = rsum(uc_var_eta uc_var_xb uc_eps)

gen var_explained_uc = tot_var_uc/var_Y
lab var var_explained_uc "Share of total variance explained (UC)"
gen var_explained_eb = tot_var_eb/var_Y
lab var var_explained_eb "Share of total variance explained (EB)"

*===============================================================================
// Tables illustrated in paper
*===============================================================================
	// Table 1
	tabstat variance_XB uc_var_xb eb_var_xb, stat(min max mean p25 p50 p75)
	//Table 2
	tabstat var_Y tot_var_uc var_explained_uc tot_var_eb var_explained_eb, stat(min max mean p25 p50 p75)


preserve 
	keep area var_explained_* tot_var*
tempfile uno
save `uno'
restore

sp_groupfunction, mean(bias_* abs_bias*) by(area)

merge m:1 area using `uno'
	drop if _m==2
	drop _m

gen ptile = real(subinstr(variable,"bias_uc_","",.))
replace ptile = real(subinstr(variable,"bias_eb_","",.)) if missing(ptile)
replace ptile = real(subinstr(variable,"abs_bias_eb_","",.)) if missing(ptile)
replace ptile = real(subinstr(variable,"abs_bias_uc_","",.)) if missing(ptile)

gen method = "Unit-Context" if regexm(variable,"uc")
replace method = "CensusEB" if regexm(variable,"eb")

gen bias_abs = "Bias" if regexm(variable,"abs_")==0
replace bias_abs = "Abs. Bias" if regexm(variable,"abs_")==1

//Export to excel for dashboards - easier to produce figures.
export excel using "$dboard\Bias_UC_EB.xlsx", sheet(sim1) first(var) sheetreplace



