set more off
clear all
if (lower("`c(username)'")=="wb378870") global main    "C:\Users\WB378870\GitHub\UC_source_of_bias\"
else global main "C:\Users\Paul Corral\Documents\GitHub\UC_source_of_bias\"
global mdata    "$main\0.data" 
global dboard "$main\4.other"

//Sp groupfunction for indicators
cap which sp_groupfunction
if (_rc){
	cap which github
	if (_rc) net install github, from("https://haghish.github.io/github/")
	github install pcorralrodas/sp_groupfunction
}


use "$mdata\source_of_bias_in_mymodel.dta", clear

// collapse to area level
groupfunction, mean(eb_* uc_* true_* mean_Y variance_XB var_Y e_y) by(area)

forval z=1/99{
	gen double bias_uc_`z' = true_`z' - uc_fgt0_`z'
	gen double bias_eb_`z' = true_`z' - eb_fgt0_`z'
	gen double abs_bias_uc_`z' = abs(bias_uc_`z')
		lab var abs_bias_uc_`z' "Absolute bias for UC model (thold `z'%)"
	gen double abs_bias_eb_`z' = abs(bias_eb_`z')
		lab var abs_bias_eb_`z' "Absolute bias for EB model (thold `z'%)"
}

gen double bias_eb_W = e_y - eb_e_y
gen double bias_uc_W = e_y - uc_e_y

gen double abs_bias_eb_W = abs(e_y - eb_e_y)
gen double abs_bias_uc_W = abs(e_y - uc_e_y)

drop eb_fgt0* uc_fgt0* true_*

gen double bias_eb_Y =  eb_Y - mean_Y
gen double bias_uc_Y =  uc_Y - mean_Y

gen double abs_bias_eb_Y =  abs(eb_Y - mean_Y)
gen double abs_bias_uc_Y =  abs(uc_Y - mean_Y)

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
	
	/*
	   stats |  varian~B  uc_var~b  eb_var~b
---------+------------------------------
     min |  .3738439  .0745521  .3738614
     max |  .8610497  .1061533  .8611119
    mean |  .5683213  .0882996  .5683544
     p25 |   .448494  .0842452  .4485162
     p50 |  .5488867  .0882529   .548916
     p75 |  .6821843  .0914306  .6822283
----------------------------------------

.         //Table 2
.         tabstat var_Y tot_var_uc var_explained_uc tot_var_eb var_explained_eb, stat(min max mean p25 p50 p75)

   stats |     var_Y  tot_va~c  var_ex~c  tot_va~b  var_ex~b
---------+--------------------------------------------------
     min |  .6316622  .8127387  .7439535  .6319045  .9975411
     max |  1.119477  .8443398  1.294781  1.119155  1.003149
    mean |  .8263428  .8264861  1.025601  .8263975  1.000069
     p25 |  .7071158  .8224318   .879407  .7065593  .9992496
     p50 |  .8076134  .8264395  1.023914  .8069591  1.000041
     p75 |  .9399566  .8296171  1.166005  .9402714  1.000613
------------------------------------------------------------

	
	
	
	*/


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
