/*******************************************************************************
  Converting district-level data to 1991 local authority districts (LAD91)
  using population weights

  Workshop:  ADR England Research Community Catalyst - Youth Transitions,
             ONS Longitudinal Study workshop, 5 November 2026
             Session: Challenges and solutions of data harmonisation
  Author:    Min Zhang, Centre for Employment Research, University of Westminster
  Software:  Stata 16 or later; requires findname (ssc install findname).
  Based on:  code written in 2021 for a project on local inequality and social
             mobility; simplified for the workshop.

  WHAT IT DOES
  The ONS LS holds local authority districts on 1991 boundaries. Outside data,
  here earnings percentiles from ASHE (via Nomis), are published on later
  boundaries. This file moves the outside data onto LAD91, so it can be merged
  with the LS.

  METHOD
  1. GeoConvert gives, for each LAD91, the share of its population that falls
     in each 2011 district (LAD11). Shares are based on 2011 postcode
     populations.
  2. If 95% or more of a LAD91 falls in one LAD11, the district is treated as
     unchanged and takes that district's value.
  3. Otherwise the LAD91 value is the population-weighted sum:
        value(LAD91) = sum over targets of  share x value(LAD11)
     e.g. district A split 70/30 into B and C:  0.7 x value(B) + 0.3 x value(C)

  INPUTS (place in the folder set in ${data}; see README for sources)
    LAD_(April_1991)_Names_and_Codes_in_England_and_Wales.csv
                             LAD91 names and codes (ONS)
    geoconvert_lad91_to_lad11.csv
                             LAD91 to LAD11 population shares (GeoConvert)
    nomis_2021_05_14_p10_p50_p90.xlsx
                             ASHE percentiles by district (Nomis), one sheet
                             per percentile, named "10 percentile" etc.

  OUTPUT
    ${output}/lad91_ashe.dta   one row per LAD91 with converted values

  Assumption: within each LAD11 the value is uniform, so a part-district
  takes the value of the whole district it moved into.
*******************************************************************************/

clear all
set more off

*-------------------------------------------------------------------------------
* 0. Settings: change these paths
*-------------------------------------------------------------------------------
global data   "C:/path/to/input"
global temp   "C:/path/to/temp"
global output "C:/path/to/output"

* This file uses findname (user-written). Install it once with:
* ssc install findname

* Threshold for treating a district as unchanged
local threshold = 0.95

* Years of ASHE to average over
local y0 = 2002
local y1 = 2011


*-------------------------------------------------------------------------------
* 1. LAD91 names
*-------------------------------------------------------------------------------
import delimited using "${data}/LAD_(April_1991)_Names_and_Codes_in_England_and_Wales.csv", varnames(1) clear
d,f
rename district_name lad91_nm
rename f1991_census_district_code censusdistricts
keep lad91_nm censusdistricts
save "${temp}/lad91_names", replace


*-------------------------------------------------------------------------------
* 2. LAD91 to LAD11 population shares (GeoConvert)
*-------------------------------------------------------------------------------
* LAD91: 403 districts in England and Wales (England 366, Wales 37)
import delimited using "${data}/geoconvert_lad91_to_lad11.csv", varnames(1) clear
gen lad91 = substr(censusdistricts, 3, .)      // e.g. "37PB" -> "PB"
rename v3 lad11
rename proportion_of_source_in_target share
lab var lad91 "1991 district code (LS)"
lab var lad11 "2011 district code"
lab var share "Share of LAD91 population in this LAD11"

gen country = substr(lad11, 1, 1)
keep if inlist(country, "E", "W") & lad91 != ""
capture drop v?                                 // empty columns from import
merge m:1 censusdistricts using "${temp}/lad91_names", nogen keep(1 3)


*-------------------------------------------------------------------------------
* 3. Match LAD11 codes to the codes used in the outside data
*-------------------------------------------------------------------------------
* `lad` is the district code used to merge the outside data.
clonevar lad = lad11

* Some 2011 Census outputs combine small districts with a neighbour.
* Give them back their own codes.
replace lad = "E09000001" if lad91 == "AA"           // City of London
replace lad = "E09000033" if lad91 == "AP"           // Westminster
replace lad = "E06000052" if lad11 == "E41000052"    // Cornwall
replace lad = "E06000053" if lad91 == "FD"           // Isles of Scilly

* Codes that changed after 2011 boundary changes (2013-2014)
replace lad = "E07000240" if lad == "E07000100"      // St Albans
replace lad = "E07000241" if lad == "E07000104"      // Welwyn Hatfield
replace lad = "E08000037" if lad == "E08000020"      // Gateshead
replace lad = "E06000057" if lad == "E06000048"      // Northumberland
replace lad = "E07000242" if lad == "E07000097"      // East Hertfordshire
replace lad = "E07000243" if lad == "E07000101"      // Stevenage


*-------------------------------------------------------------------------------
* 4. Classify each LAD91: unchanged or changed
*-------------------------------------------------------------------------------
gen byte main = share >= `threshold'
lab var main "This LAD11 holds >= 95% of the LAD91 population"

bys lad91: egen byte any_main = max(main)
gen byte status = cond(any_main == 1, 0, 1)
* Islington (AF) and Tower Hamlets (AM): small boundary changes with the
* City of London in 1994. Flagged for checking; treated as unchanged.
replace status = 9 if inlist(lad91, "AF", "AM")
lab def status 0 "unchanged" 1 "changed" 9 "check"
lab val status status
drop any_main

* Check: shares should sum to about 1 within each LAD91
bys lad91: egen double share_total = total(share)
lab var share_total "Sum of shares within LAD91"
sum share_total

save "${temp}/lad91_lad11_shares", replace


*-------------------------------------------------------------------------------
* 5. Outside data: ASHE percentiles by district (Nomis)
*-------------------------------------------------------------------------------
* note for missing data from the original spreadsheet: : 
*	# These figures are suppressed as statistically unreliable.
*	! Estimate and confidence interval not available since the group sample size is zero or disclosive (0-2).
*	- These figures are missing.
* all set to missing
foreach pct in 10 50 90  {
    di `pct'
	
	local sheet "nomis_2021_05_14_p10_p50_p90"

	import excel using ///
		"${data}/`sheet'.xlsx", ///
		clear cellrange(A9) sheet("`pct' percentile") firstrow allstring
	gen country = substr(B, 1, 1)
	rename B lad
	rename localauthoritydistrictunit lad_name

	* Keep England & Wales
	keep if country == "E" | country == "W"
	
* rename variables: year: 2002-2020

	local start = 2002
	d, s
	return list
	local maxcol = `r(k)'-1
	forvalues i = 3(2)`maxcol' {
		qui findname , col(`i')
		rename `r(varlist)' p`pct'_`start'
		lab var p`pct'_`start' "Year `start' income `pct'th percentile"
		replace p`pct'_`start' = "" if inlist(p`pct'_`start', "-", "#", "!")
	
		local j = `i' + 1
		qui findname , col(`j')
		rename `r(varlist)' p`pct'_`start'_se
		lab var p`pct'_`start'_se "Year `start' income `pct'th percentile, SE as a % of the figure"
		replace p`pct'_`start'_se = "" if inlist(p`pct'_`start'_se, "-", "#", "!")
	
		local start = `start' + 1
}

	destring p`pct'_*, replace 

	save "${temp}/ashe_p`pct'", replace
}

use "${temp}/ashe_p10", clear
foreach p in 50 90 {
    merge 1:1 lad using "${temp}/ashe_p`p'", nogen
}

* Ratios for each year, then the average over `y0'-`y1'
forvalues y = `y0'/`y1' {
    gen r9010_`y' = p90_`y' / p10_`y'
    gen r9050_`y' = p90_`y' / p50_`y'
}
foreach m in r9010 r9050 p50 {
    local keepv
    forvalues y = `y0'/`y1' {
        local keepv `keepv' `m'_`y'
    }
    egen `m'_avg = rowmean(`keepv')
}
lab var r9010_avg "90/10 earnings ratio, `y0'-`y1' average"
lab var r9050_avg "90/50 earnings ratio, `y0'-`y1' average"
lab var p50_avg   "Median earnings, `y0'-`y1' average"
keep lad *_avg
save "${temp}/ashe_district", replace


*-------------------------------------------------------------------------------
* 6. Population-weighted conversion to LAD91
*-------------------------------------------------------------------------------
use "${temp}/lad91_lad11_shares", clear
merge m:1 lad using "${temp}/ashe_district", keep(master match)
tab _merge
drop _merge

* Note on Ryedale (PB) and Selby (PD): these are the two largest splits in
* England. In 1996 the new York unitary authority took 15 parishes from
* Ryedale and 13 from Selby. Their weights rest on 2011
* populations, and the York suburbs grew after 1991. 
* They are converted in the same way as every other district; 
* check results for these two if York matters.

foreach v in r9010_avg r9050_avg p50_avg {
    * Changed districts: weighted sum over all target districts
    bys lad91: egen double `v'_91 = total(share * `v') if status == 1
    * Unchanged districts: value of the main target district
    replace `v'_91 = `v' if inlist(status, 0, 9) & main == 1
    * Copy to every row of the LAD91
    bys lad91 (share): replace `v'_91 = `v'_91[_N] if missing(`v'_91)
}
lab var r9010_avg_91 "90/10 earnings ratio, LAD91"
lab var r9050_avg_91 "90/50 earnings ratio, LAD91"
lab var p50_avg_91   "Median earnings, LAD91"

* One row per LAD91 (keep the target district with the largest share)
bys lad91 (share): keep if _n == _N
keep lad91 lad91_nm country status share_total *_91
order lad91 lad91_nm country status share_total
count                                           // expect 403
save "${output}/lad91_ashe", replace

* The file can now be merged onto LS records by their 1991 district code.
