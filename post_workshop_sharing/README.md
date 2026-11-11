# Population-weighted conversion to 1991 local authority districts

Code shared at the ADR England Research Community Catalyst: Youth Transitions workshop on the ONS Longitudinal Study (5 November 2026), from the session *Challenges and solutions of data harmonisation*.

The ONS LS holds local authority districts on 1991 boundaries (LAD91). Data from outside the LS, such as earnings from ASHE, are published on later boundaries. `LAD91_population_weighted_conversion.do` moves district-level data onto LAD91 so it can be linked to LS records.

## Method

1. **Population shares.** GeoConvert gives the share of each LAD91's population that lies in each 2011 district (LAD11), based on 2011 postcode populations.
2. **95% rule.** If at least 95% of a LAD91 lies in one LAD11, the district is treated as unchanged and takes that district's value.
3. **Weighted sum.** Otherwise, value(LAD91) = Σ share × value(LAD11). For example, if district A splits 70/30 into B and C, A = 0.7 × B + 0.3 × C.

This assumes values are uniform within each LAD11.

## Inputs

Save these in the folder set by `${data}` at the top of the do-file. They are not included in this repository.

| File | Contents | Source |
|---|---|---|
| `LAD_(April_1991)_Names_and_Codes_in_England_and_Wales.csv` | LAD91 names and codes | ONS Open Geography Portal: *Local Authority Districts (April 1991) Names and Codes in England and Wales* |
| `geoconvert_lad91_to_lad11.csv` | LAD91 to LAD11 population shares | UK Data Service GeoConvert |
| `nomis_2021_05_14_p10_p50_p90.xlsx` | ASHE earnings percentiles (10th, 50th, 90th) by district, one sheet per percentile | Nomis |

## Running it

1. Set the three paths at the top of the do-file.
2. Install `findname` once (`ssc install findname`), then run the do-file in Stata 16 or later.
3. The output is `lad91_ashe.dta`, with one row per LAD91 (403 districts in England and Wales).

To convert a different variable, replace section 5 with your own district-level file keyed on `lad`, and list your variables in the loop in section 6.

## Points to check

- **Special cases.** City of London, Westminster, Cornwall and the Isles of Scilly are combined in some 2011 outputs. Several codes also changed in 2013–14. Section 3 deals with both.
- **Islington and Tower Hamlets** are flagged `status == 9` because of small boundary changes in 1994.
- **Ryedale and Selby** lost large areas to the new York unitary authority in 1996. Their weights rest on 2011 populations, so check results for these two districts if York matters to your analysis.

## Author

Min Zhang, Centre for Employment Research, University of Westminster.
