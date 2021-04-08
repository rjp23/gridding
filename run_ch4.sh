julia ./gridL2_Dates.jl --help
usage: gridL2_Dates.jl [--Dict DICT] [-o OUTFILE] [--monthly]
                       [--compSTD] [--latMin LATMIN] [--latMax LATMAX]
                       [--lonMin LONMIN] [--lonMax LONMAX]
                       [--dLat DLAT] [--dLon DLON]
                       [--startDate STARTDATE] [--stopDate STOPDATE]
                       [--dDays DDAYS] [-h]



julia ./gridL2_Dates.jl --dLat 0.25 --dLon 0.25  --dDays 1 --monthly --startDate 2017-11-01 --stopDate 2020-07-31  --Dict jsonFiles/tropomi_all_rob.json  -o tropomi_sif_monthly_test.nc

/gws/nopw/j04/esa_dte/input-data/eo-data/TROPOMI_SIF


2017-11-01

2020-07-31




julia ./gridL2_Dates.jl --dLat 0.1 --dLon 0.1  --dDays 1  --startDate 2017-11-01 --stopDate 2020-07-31  --Dict jsonFiles/tropomi_bremen_ch4.json  -o s5p_bremen_ch4_test_01.nc
