set more off
clear all
global main    "C:\Users\WB378870\GitHub\UC_source_of_bias\"
global mdata    "$main\0.data" 
global dboards "$main\4.other"

cap set processors 4

/*
Author: Paul Corral
Version @2 differs from previous one in that we create a model where 
UC models have a better fit (R2 ~ 0.18), also welfare is somewhat more skewed


We start off by creating a fake data set illustrated in Marhuenda et al. (2017).
 https://rss.onlinelibrary.wiley.com/doi/pdf/10.1111/rssa.12306
*/
/*
Purpose of file is to test SAE model performance by imputing on to the 
population instead of a sample. This should remove all other sources of bias.
*/

*===============================================================================
// Parameters for simulated data set
*===============================================================================
	version 15
	set seed 734137
	global numobs = 500000
	global areasize  = 5000
	global psusize   = 1000
	
	//We have 2 location effects below
	global sigmaeta_psu   = 0.1  
	global sigmaeta_area  = 0.15
	//We have household specific errors
	global sigmaeps   = 0.5
	//Poverty line fixed at 26
	global  pline  = 26
	global lnpline = ln($pline)
	//locals
	local obsnum    = $numobs
	local areasize  = $areasize
	local psusize   = $psusize
	local total_sim = 1000
	local myrep     = 50
	local from0     = 1
	
*===============================================================================
//1.Create simulated data
*===============================================================================
//Start off with # of observations
set obs `=`obsnum'/`areasize''	
	gen area = _n
		lab var area "Area identifier"
	//expand to create 10 psu per area
	expand `=`areasize'/`psusize''
	sort area
	//PSUs labelled from 1 to 10 within each area
	gen psu = _n - (area-1)*`=`areasize'/`psusize''
		lab var psu "PSU identifier"
	//expand to create 50 observations by psu	
	expand `psusize'
	sort area psu
	//Household id
	gen hhid = _n
		lab var hhid "Household identifier"
		
	//Covariates, some are corrlated to the area and psu's label
	gen x1=runiform()<=(0.3+.5*area/(`obsnum'/`areasize') + ///
	0.2*psu/(`areasize'/`psusize'))
	gen x2=runiform()<=(0.2)
	gen x3= runiform()<=(0.1 + .2*area/int(`obsnum'/`areasize'))
	gen x4= runiform()<=(0.5+0.3*area/int(`obsnum'/`areasize') + ///
	0.1*psu/int(`areasize'/`psusize'))
	gen x5= round(max(1,rpoisson(3)*(1-.1*area/int(`obsnum'/`areasize'))),1)
	gen x6= runiform()<=0.4
	gen x7=rpoisson(3)*(1*psu/int(`areasize'/`psusize')- 1*area/int(`obsnum'/`areasize')+ 1*uniform())
	
	//note that this matches the model from eq. 3 of Corral et al. (2021)
	gen XB = 3+ .09* x1-.04* x2 - 0.09*x3 + 0.4*x4 - 0.25*x5 + 0.1*x6 + 0.33*x7
		lab var XB "Linear fit"
		
//Create psu level means...
groupfunction, mean(x*) merge by(area psu)
//Create area level variance
groupfunction, var(XB)  merge by(area)
//Indicate first area observation
bysort area: gen area_1st = 1 if _n==1
//Indicate first psu observation
bysort area psu: gen psu_1st = 1 if _n==1
sort hhid
//We need weights for SAE command
gen hhsize = 1
lab var hhsize "HH size for command"
//Save population's Xs and linear fit
//random area effects
	gen double eta_a = rnormal(0,$sigmaeta_area) if area_1st==1
	replace eta_a = eta_a[_n-1] if missing(eta_a)
	gen double eta_p = rnormal(0,$sigmaeta_psu) if psu_1st ==1
	replace eta_p = eta_p[_n-1] if missing(eta_p)
	//household errors
	gen eps = rnormal(0,$sigmaeps)
	//Y, normally distributed
	egen double Y = rsum(XB eta_a eta_p eps)
	
	
	pctile double y_p = Y, nq(100)
	forval z=1/99{
		gen pline_`z' = y_p[`z']
	}
	
	drop eta_a eta_p eps Y
	
save "$mdata\popX_source_of_bias.dta", replace

*===============================================================================
//2. Run the simulations
*===============================================================================
/*
Now, we will run 1,000 simulations where we follow the model's assumpitons.
under each simulation we will add to XB the psu and area effect, as well
as the household specific error.
Then, under each population we will obtain CensusEB estimates under
unit-level CensusEB, and unit-context models. For each
population and the EB estimates obtained we will calculate the difference
between the true poverty rate and the estimate, and the squared difference.
After 1000 simulations these are our empirical bias and MSE.
*/
//Add random location effects and household errors
forval Zim=1/`total_sim'{
	use "$mdata\popX_source_of_bias.dta", clear
	//random area effects
	gen double eta_a = rnormal(0,$sigmaeta_area) if area_1st==1
	replace eta_a = eta_a[_n-1] if missing(eta_a)
	gen double eta_p = rnormal(0,$sigmaeta_psu) if psu_1st ==1
	replace eta_p = eta_p[_n-1] if missing(eta_p)
	//household errors
	gen eps = rnormal(0,$sigmaeps)
	//Y, normally distributed
	egen double Y = rsum(XB eta_a eta_p eps)
	tempfile myPop
	save `myPop'
	//Seed stage for simulations, changes after every iteration!
	local seedstage `c(rngstate)'
	preserve
		//true values by area
		forval z=1/99{
			gen true_`z' = Y<pline_`z' if !missing(Y)
		}
		gen var_Y = Y
		gen mean_Y = Y
		groupfunction [aw=hhsize], mean(true_* mean_Y) first(variance_XB) variance(var_Y) by(area)
		tempfile true
		save `true'
	restore
    //Without transforming...CensusEB
    use `myPop', clear
		xtmixed Y  x1 x2 x3 x4 x5 x6 x7 ||area:, reml
		predict fit_xb, fitted
		//Estimated variances
		local uvar =  (exp([lns1_1_1]_cons))^2 //location
		local evar =  (exp([lnsig_e]_cons))^2  //Idiosyncratic
		//Produce location specific variance
		egen numobs_area = sum(!missing(Y)), by(area) //number of observations in area
		gen double gamma  = `uvar'/(`uvar'+`evar'/numobs_area) //Gamma or adjustment factor
		gen double var_eta = `uvar'*(1-gamma)
		
		//Get probability of falling under each of the different percentiles
		forval z=1/99{
			gen double eb_fgt0_`z'  = normal((pline_`z' - fit_xb)/(sqrt(var_eta+`evar')))
		}	
		
		gen eb_var_xb = fit_xb 
		gen eb_Y = fit_xb
		groupfunction, mean(eb_fgt0_* var_eta eb_Y) var(eb_var_xb) by(area)
		
		rename var_eta eb_var_eta
		gen eb_eps = `evar'
		
	tempfile h3ebn
	save `h3ebn'

	
	//Obtain UC SAE, without transforming
	use `myPop', clear
		xtmixed Y mean_x1 mean_x2 mean_x3 mean_x4 mean_x5 mean_x6 mean_x7 ||area:, reml
		predict fit_xb, fitted
		//Estimated variances
		local uvar =  (exp([lns1_1_1]_cons))^2 //location
		local evar =  (exp([lnsig_e]_cons))^2  //Idiosyncratic
		//Produce location specific variance
		egen numobs_area = sum(!missing(Y)), by(area) //number of observations in area
		gen double gamma  = `uvar'/(`uvar'+`evar'/numobs_area) //Gamma or adjustment factor
		gen double var_eta = `uvar'*(1-gamma)
		
		//Get probability of falling under each of the different percentiles
		forval z=1/99{
			gen double uc_fgt0_`z'  = normal((pline_`z' - fit_xb)/(sqrt(var_eta+`evar')))
		}
		gen uc_var_xb = fit_xb 
		gen uc_Y = fit_xb
		groupfunction, mean(uc_fgt0_* var_eta uc_Y) var(uc_var_xb) by(area)		
		rename var_eta uc_var_eta		
		gen uc_eps = `evar'
	tempfile h3arean
	save `h3arean'	
		
	//Open true point estimates
	use `true', clear
	//Merge in the model based estimates
	merge 1:1 area using `h3arean', keepusing(uc_*)
		drop _m
	merge 1:1 area using `h3ebn' , keepusing(eb_*)
		drop _m
	gen sim = "`Zim'"
	cap: append using `elcompleto'
	tempfile elcompleto
	save `elcompleto'	
}
save "$mdata\source_of_bias_in_mymodel.dta", replace
