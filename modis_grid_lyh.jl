using ArgParse
using Base, Dates, Printf
# NetCDF tools for reading and writing
using NCDatasets
# Basic statistics
using Statistics
# File search and completion
using Glob
# JSON files
import JSON
# Parallel computing
using Distributed, SharedArrays, DataStructures
# Profiler
using Profile
using ProgressMeter

function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table s begin
    	"--Dict"
            help = "JSON dictionary file to use"
            arg_type = String
            #default = "/home/cfranken/code/gitHub/Gridding/gridding/modis_all.json"
            default = "/home/lyh/modis_all.json"
        "--outFile", "-o"
            help = "output filename"
            arg_type = String
            #default = "MODIS_map.nc"
            default = "/home/lyh/MODIS_map.nc"
		"--monthly"
	        help = "Use time-steps in terms of months (not days)"
	        action = :store_true
        "--latMin"
            help = "Lower latitude bound"
            arg_type = Float32
            default = -90.0f0
        "--latMax"
            help = "Upper latitude bound"
            arg_type = Float32
            default = 90.0f0
        "--lonMin"
            help = "Lower longitude bound"
            arg_type = Float32
            default = -180.0f0
        "--lonMax"
            help = "Upper longitude bound"
            arg_type = Float32
            default = 180.0f0
        "--dLat"
            help = "latitude resolution"
            arg_type = Float32
            #default = 1.0f0
            default = 0.5f0
        "--dLon"
            help = "longitude resolution"
            arg_type = Float32
            #default = 1.0f0
            default = 0.5f0
		"--startDate"
	            help = "Start Date (in YYYY-MM-DD)"
	            arg_type = String
	            #default = "2018-03-07"
                default = "2018-07-15"
		"--stopDate"
			    help = "Stop Date (in YYYY-MM-DD)"
			    arg_type = String
			    #default = "2018-10-31"
                default = "2018-07-16"
		"--dDays"
				help = "Time steps in days (or months if --monthly is set)"
				arg_type = Int64
				#default = 8
                default = 1
    end
    return parse_args(s)
end

L=1/0.0001
C1 = 6.
C2 = 7.5
G  = 2.5

function aver!(mat_data, mat_in, iLon_,iLat_, idx)
	NDVI = zeros(Float32,1)
	d = size(mat_in)
	for i = 1:length(idx)
		A = view(mat_in,idx[i][2],idx[i][1],1:d[3]-1)
		if !any(A.==32767)
			# NIR reflectance > 0.01, gets rid of water
			if(A[2]*0.0001>0.03)
				for j=1:d[3]-1
					mat_data[iLon_[i],iLat_[i],j] +=  mat_in[idx[i][2],idx[i][1],j]*0.0001
				end
				# Compute vegetation indices here:
				# EVI
				mat_data[iLon_[i],iLat_[i],d[3]] +=G*(A[2]-A[1])/(A[2]+C1*A[1]-C2*A[4]+L)
				# NDVI
				NDVI[1] = (A[2]-A[1])/(A[2]+A[1])
				#println(NDVI, " ", A[2]*0.0001, " ", A[1]*0.0001, " ", NDVI[1]*A[2]*0.0001," ", (A[2]*0.0001-A[1]*0.0001)/(A[2]*0.0001+A[1]*0.0001))

				mat_data[iLon_[i],iLat_[i],d[3]+1] += NDVI[1]
				#println(mat_data[iLon_[i],iLat_[i],d[3]+1] ," ", mat_data[iLon_[i],iLat_[i],2] )
				# NIRv
				mat_data[iLon_[i],iLat_[i],d[3]+2] += NDVI[1]*A[2]*0.0001
				# NWDI
				mat_data[iLon_[i],iLat_[i],d[3]+3] +=(A[2]-A[5])/(A[2]+A[5])
				# N
				mat_data[iLon_[i],iLat_[i],end] +=   mat_in[idx[i][2],idx[i][1],end]
			end
		end
	end
end

function main()

	#addprocs()
    # Parse command line arguments
    ar = parse_commandline()

	# Find files to be processed
	startDate = DateTime(ar["startDate"])
	stopDate = DateTime(ar["stopDate"])
	if ar["monthly"]
		dDay = Dates.Month(ar["dDays"])
	else
		dDay = Dates.Day(ar["dDays"])
	end
	println(startDate, " ", stopDate)
	cT = length(startDate:dDay:stopDate)


    # Just lazy (too cumbersome in code as often used variables here)
    latMax = ar["latMax"]
    latMin = ar["latMin"]
    lonMax = ar["lonMax"]
    lonMin = ar["lonMin"]
    dLat = ar["dLat"]
    dLon = ar["dLon"]
    eps = dLat/100

    # Define spatial grid:
    lat = collect(latMin+dLat/2.:dLat:latMax-dLat/2.0+eps)
    lon = collect(lonMin+dLon/2.:dLon:lonMax-dLon/2.0+eps)
	println("Output file dimension (time/lon/lat):")
    println(cT, "/", length(lon),"/", length(lat))
    # Create output file:
    dsOut = Dataset(ar["outFile"],"c")
    defDim(dsOut,"lon",length(lon))
	defDim(dsOut,"lat",length(lat))
	defDim(dsOut,"time", cT)
	dsLat = defVar(dsOut,"lat",Float32,("lat",), attrib = ["units" => "degrees_north","long_name" => "Latitude"])
	dsLon = defVar(dsOut,"lon",Float32,("lon",), attrib = ["units" => "degrees_east","long_name" => "Longitude"])
	dsTime= defVar(dsOut,"time",Float32,("time",),attrib = ["units" => "days since 1970-01-01","long_name" => "Time (UTC), start of interval"])
	dsLat[:]=lat
	dsLon[:]=lon


	# Define a global attribute
	dsOut.attrib["title"] = "Awesome gridded file"

    # Define gridded variables:
    n=zeros(Float32,(length(lat),length(lon)))
    SIF = zeros(Float32,(length(lat),length(lon)))
    # Parse JSON files as dictionary
	jsonDict = JSON.parsefile(ar["Dict"], dicttype=DataStructures.OrderedDict)
    #d2 = jsonDict["basic"]
    dGrid = jsonDict["grid"]
	# Get file naming pattern (needs YYYY MM and DD in there)
	fPattern = jsonDict["filePattern"]
	# Get main folder for files:
	folder = jsonDict["folder"]

	NCDict= Dict{String, NCDatasets.CFVariable}()
	println("Creating NC datasets in output:")
	for (key, value) in dGrid
		print(key," ")
		NCDict[key] = defVar(dsOut,key,Float32,("time","lon","lat"),deflatelevel=4, fillvalue=-999)
	end
	ds_ndvi = defVar(dsOut,"NDVI",Float32,("time","lon","lat"),deflatelevel=4, fillvalue=-999)
	ds_evi = defVar(dsOut,"EVI",Float32,("time","lon","lat"),deflatelevel=4, fillvalue=-999)
	ds_nirv = defVar(dsOut,"NIRv",Float32,("time","lon","lat"),deflatelevel=4, fillvalue=-999)
	ds_ndwi = defVar(dsOut,"NDWI",Float32,("time","lon","lat"),deflatelevel=4, fillvalue=-999)

	println(" ")
	#dSIF = defVar(dsOut,"sif",Float32,("lon","lat"),deflatelevel=4, fillvalue=-999)
	dN = defVar(dsOut,"n",Float32,("time","lon","lat"),deflatelevel=4, fillvalue=-999)
    # Define data array
	# How many additional dataset (here, NDVI, EVI, NIRv and NDWI)
	addData = 4
    mat_data= zeros(Float32,(length(lon),length(lat),addData+1+length(dGrid)))
	mat_in =  zeros(Float32,2400,2400,length(dGrid)+1)

	ds = Dataset("/home/lyh/test_wholedata.nc","r")
	lon_table = ds["longitude"]
	lat_table = ds["latitude"]

	# Loop through time:
	# Time counter
	cT = 1
	p1 = Progress(cT)
	for d in startDate:dDay:stopDate
		ProgressMeter.next!(p1; showvalues = [(:Time, d)])
		files = String[];
		# Step through 8 days here, otherwise overkill
		for di in d:Dates.Day(1):d+dDay-Dates.Day(1)

			#********* This needs to be updated to use the Day of Year (and not MM and DD)!! *********#
			# filePattern = reduce(replace,["YYYY" => lpad(Dates.year(di),4,"0"), "MM" => lpad(Dates.month(di),2,"0"),  "DD" => lpad(Dates.day(di),2,"0")], init=fPattern)
			filePattern = reduce(replace,["YYYY" => lpad(Dates.year(di),4,"0"),  "MM" => lpad(Dates.month(di),2,"0"),  "DD" => lpad(Dates.day(di),2,"0"), "DOY" => lpad(Dates.dayofyear(di),3,"0")], init=fPattern)
			folderPattern = reduce(replace,["YYYY" => lpad(Dates.year(di),4,"0"),  "MM" => lpad(Dates.month(di),2,"0"),  "DD" => lpad(Dates.day(di),2,"0")], init=folder)
            println(filePattern)
			files = [files;glob(filePattern, folderPattern)]
		end
		#println(files)

    	# Loop through all files
		n = length(files)
    	p = Progress(n)   # minimum update interval: 1 second
	    for a in files

	        # Read NC file
	        fin = Dataset(a)
	        # Check lat/lon first to see what data to read in

			#********* Here you need to read in lat/lon from MODIS (table or calculate on the fly) *********#
			#lat_in = fin[d2["lat"]].var[:]
	        #lon_in = fin[d2["lon"]].var[:]

            pos_start = findfirst("MCD43A4.A", a)
            filename = a[pos_start[1]:end]
            h = parse(Int32,filename[19:20])
            v = parse(Int32,filename[22:23])

            lon_in_ = lon_table[h+1,v+1,:,:]
            lat_in_ = lat_table[h+1,v+1,:,:]

			# Call the variables lat_in and lon_in and then best
	        #lat_in_ = fin[d2["lat_bnd"]].var[:]
	        #lon_in_ = fin[d2["lon_bnd"]].var[:]
			#dim = size(lat_in_)

			# Get indices within the lat/lon boudning box:
			#idx = findall((minLat[:,1].>latMin).&(maxLat[:,1].<latMax).&(minLon[:,1].>lonMin).&(maxLon[:,1].<lonMax))
            idx = findall((lat_in_.>latMin).&(lat_in_.<latMax).&(lon_in_.>lonMin).&(lon_in_.<lonMax))
			ProgressMeter.next!(p; showvalues = [(:File, a), (:N_pixels, size(idx))])
			#println("Size of idx ", size(idx), " lat_in_ ", size(lat_in_))
			# Read data only for non-empty indices
	        if length(idx) > 0
				#print(size(lat_in_))

				dim = size(mat_in)
	            # Read in all entries defined in JSON file:
				co = 1
				# This should just read in the datasets:
	            for (key, value) in dGrid
					#println(key, value)
	            	mat_in[:,:,co]=fin[value].var[:]
					co += 1
	            end
	            mat_in[:,:,end].=1
				# This computes the indices into which the respective lats and lons are falling into.
	            #iLat_ = ((lat_in[idx].-latMin)/(latMax-latMin)*length(lat)).+1
	            #iLon_ = ((lon_in[idx].-lonMin)/(lonMax-lonMin)*length(lon)).+1
                iLat_ = round.(Int64,((lat_in_[idx].-latMin)/(latMax-latMin)*length(lat)).+0.5.-1e-6,RoundNearestTiesAway)
                iLon_ = round.(Int64,((lon_in_[idx].-lonMin)/(lonMax-lonMin)*length(lon)).+0.5.-1e-6,RoundNearestTiesAway)
				# Once you have done this, we can chat about the gridding itself (just a few lines of code here)

				aver!(mat_data, mat_in, iLon_,iLat_, idx)
				fill!(mat_in,0.0)
	            #println("Read ", a, " ", length(idx))
	        else
	            #println("Read ", a, " ", length(idx))
	        end
	        close(fin)
	    end
		# Filter all data, set averages
		dims = size(mat_data)
		println("Averaging final product...")

		NN = mat_data[:,:,end]
		dN[cT,:,:]=NN
		# Write out time:
		dsTime[cT]=d
		co = 1
		thr = 5
		for (key, value) in dGrid
			da = round.(mat_data[:,:,co]./mat_data[:,:,end],sigdigits=5)
			#println(maximum(da), " ", maximum(NN))
			#da[NN.<1e-10].=-999
            da[NN.<thr].=-999
			NCDict[key][cT,:,:]=da
			co += 1
		end
		d = size(mat_in)
		println(d)
		da = round.(mat_data[:,:,d[3]]./mat_data[:,:,end],sigdigits=5)

		da[NN.<thr].=-999
		ds_evi[cT,:,:] = da
		da = round.(mat_data[:,:,d[3]+1]./mat_data[:,:,end],sigdigits=5)
		da[NN.<thr].=-999
		ds_ndvi[cT,:,:] = da
		da = round.(mat_data[:,:,d[3]+2]./mat_data[:,:,end],sigdigits=5)
		da[NN.<thr].=-999
		ds_nirv[cT,:,:] = da
		da = round.(mat_data[:,:,d[3]+3]./mat_data[:,:,end],sigdigits=5)
		da[NN.<thr].=-999
		ds_ndwi[cT,:,:] = da
		cT += 1
		fill!(mat_data,0.0)
	end
	close(dsOut)
	close(ds)
end

main()
