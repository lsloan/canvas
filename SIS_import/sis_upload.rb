#!/usr/bin/env ruby

require "json"
require "fileutils"
require "rubygems"
require "nokogiri"
require "digest"
require "rest-client"
require "zip/zip"
require "uri"
require "addressable/uri"
require "set"

require_relative "utils.rb"

# there should be two command line argument when invoking this Ruby script
# like ruby ./SIS_upload.rb <the_token_file_path> <the_properties_file_path>

# the security file name
securityFile = ""
# the properties file name
propertiesFile = ""

# the access token
$token = ""
# the Canvas server name
$server = ""
# the Canvas server api url
$server_api_url = ""
# the current working directory, archive directory and output directory
$currentDirectory=""
$archiveDirectory=""
$outputDirectory=""

# the warning message from upload process
$upload_warnings = ""

# the interval in seconds between API calls to check upload process status
$sleep = 10

# the alert email address is read from the configuration file
# and defaults to "canvas-sis-data-alerts@umich.edu", if not set otherwise
$alert_email_address = "canvas-sis-data-alerts@umich.edu"


# for sandbox site creation purpose: looking for users with teacher role, with active enrollment status, both defined in the enrollment file
TEACHER_ROLE_ARRAY = ["teacher", "ta"]
ACTIVE_STATUS = 'active'
ENROLLMENTS_FILE_NAME = 'enrollments.csv'

# placeholder for user sandbox site title
USERNAME="USERNAME"
PREVIOUS_USER_SANDBOX_NAME = "A Canvas training course for #{USERNAME}"
TARGET_USER_SANDBOX_NAME = "#{USERNAME}'s Practice Course"

# Canvas account number
ACCOUNT_NUMBER = 1

# the path of Canvas API call
API_PATH="/api/v1/"


# variables for Canva API call throttling
@Canvas_call_count = 0
@Canvas_start_time = Time.now
@Canvas_time_interval_in_seconds = 3600
@Canvas_end_time = @Canvas_start_time + @Canvas_time_interval_in_seconds # one minute apart
@Canvas_allowed_call_number_during_interval = 3000

# make sure the Canvas call is within API usage quota
def Canvas_API_CALL_check
	call_hash = sleep_according_to_timer_and_api_call_limit(@Canvas_start_time, @Canvas_end_time, @Canvas_call_count, @Canvas_time_interval_in_seconds, @Canvas_allowed_call_number_during_interval)
	@Canvas_start_time = call_hash["start_time"]
	@Canvas_end_time = call_hash["end_time"]
	@Canvas_call_count = call_hash["call_count"]
end

# Ruby URI.escape has been deprecated.
# Addressable::URI.escape seems to be a viable solution, which offers url encoding, form encoding and normalizes URLs.
# http://stackoverflow.com/questions/2824126/whats-the-difference-between-uri-escape-and-cgi-escape

## make Canvas API GET call
def Canvas_API_GET(url)
	# make sure the Canvas call is within API usage quota
	Canvas_API_CALL_check()

	begin
		response = RestClient.get Addressable::URI.escape(url), {:Authorization => "Bearer #{$token}",
	                                :accept => "application/json",
	                                :verify_ssl => true}
		return json_parse_safe(url, response, nil)
	rescue => e
		return json_parse_safe(url, e.response, nil)
	end
end

## make Canvas API POST call
def Canvas_API_POST(url, post_params)
	# make sure the Canvas call is within API usage quota
	Canvas_API_CALL_check()

	begin
		response = RestClient.post Addressable::URI.escape(url), post_params,
		                           {:Authorization => "Bearer #{$token}",
		                            :accept => "application/json",
		                            :content_type => "application/json",
		                            :verify_ssl => true}
		return json_parse_safe(url, response, nil)
	rescue => e
		return json_parse_safe(url, e.response, nil)
	end
end

## make Canvas API POST call
def Canvas_API_PUT(url, post_params)
	# make sure the Canvas call is within API usage quota
	Canvas_API_CALL_check()

	begin
		response = RestClient.put Addressable::URI.escape(url), post_params,
		                           {:Authorization => "Bearer #{$token}",
		                            :accept => "application/json",
		                            :content_type => "application/json",
		                            :verify_ssl => true}
		return json_parse_safe(url, response, nil)
	rescue => e
		return json_parse_safe(url, e.response, nil)
	end
end

## make Canvas API POST call
def Canvas_API_IMPORT(url, fileName)
	# make sure the Canvas call is within API usage quota
	Canvas_API_CALL_check()

	begin
		response = RestClient.post Addressable::URI.escape(url), {:multipart => true,
																	 :attachment => File.new(fileName, 'rb')
																	},
																	{:Authorization => "Bearer #{$token}",
	                                :accept => "application/json",
	                                :import_type => "instructure_csv",
	                                :content_type => "application/zip",
	                                :verify_ssl => true}
		return json_parse_safe(url, response, nil)
	rescue => e
		return json_parse_safe(url, e.response, nil)
	end
end

def upload_to_canvas(fileName, outputFile, output_file_base_name)

	# set the error flag, default to be false
	upload_error = false

	# prior to upload current zip file, make an attempt to check the prior upload, whether it is finished successfully
	if (prior_upload_error)
		return "Previous upload job has not finished yet."
	end

	# upload start time
	outputFile.write("upload start time : " + Time.new.inspect)

	# continue the current upload process
	parsed = Canvas_API_IMPORT("#{$server_api_url}accounts/#{ACCOUNT_NUMBER}/sis_imports.json", fileName)

	if (parsed["errors"])
		## break and print error
		error_array=parsed["errors"]
		## hashmap ["message"=>"error_message"
		upload_error = error_array[0]["message"]
		outputFile.write("upload error: " + upload_error)
		outputFile.write("\n")

		return upload_error
	end

	job_id=parsed["id"]

	begin
		#open a separate file to log the job id
		outputIdFile = File.open($outputDirectory + output_file_base_name + "_id.txt", "w")
		# write the job id into the id file
		outputIdFile.write(job_id);
	ensure
		outputIdFile.close unless outputIdFile == nil
	end

	outputFile.write("the job id is: #{job_id}\n")
	outputFile.write("here is the job #{job_id} status: \n")

	begin
		#sleep every 10 sec, before checking the status again
		sleep($sleep);

		parsed_result = Canvas_API_GET("#{$server_api_url}accounts/#{ACCOUNT_NUMBER}/sis_imports/#{job_id}")

		#print out the whole json result
		outputFile.write("#{parsed_result}\n")

		if (parsed_result["errors"])
			## break and print error
			if (parsed_result["errors"].is_a? Array and parsed_result["errors"][0]["message"])
				# example error message
				# {"errors":[{"message":"An error occurred.","error_code":"internal_server_error"}],"error_report_id":237849}
				upload_error = parsed_result["errors"][0]["message"]
			else
				upload_error = parsed_result["errors"]
			end
			## hashmap ["message"=>"error_message"
			outputFile.write("upload error: " + upload_error)
			outputFile.write("\n")

			break
		else
			job_progress=parsed_result["progress"]
			outputFile.write("processed #{job_progress}\n")
		end
	end until job_progress == 100

	if (!upload_error)
		# print out the process warning, if any
		if (parsed_result["processing_errors"])
			outputFile.write("upload process errors: #{parsed_result["processing_errors"]}\n")
		elsif (parsed_result["processing_warnings"])
			#parsed_result = {"created_at" =>"2015-04-27T19:00:04Z",
			#                 "started_at"=>"2015-04-27T19:00:04Z",
			#                 "ended_at" =>"2015-04-27T19:06:29Z",
			#                 "updated_at"=>"2015-04-27T19:06:29Z",
			#                 "progress"=>100,
			#                 "id"=>429,
			#                 "workflow_state"=>"imported_with_messages",
			#                 "data"=>{"import_type"=>"instructure_csv",
			#                          "supplied_batches"=>["course","section","user","enrollment"],
			#                          "counts"=>{"accounts"=>0,
			#                                     "terms"=>0,
			#                                     "abstract_courses"=>0,
			#                                     "courses"=>488,
			#                                     "sections"=>488,
			#                                     "xlists"=>0,
			#                                     "users"=>606,
			#                                     "enrollments"=>1178,
			#                                     "groups"=>0,
			#                                     "group_memberships"=>0,
			#                                    "grade_publishing_results"=>0}},
			#                 "batch_mode"=>null,
			#                 "batch_mode_term_id"=>null,
			#                 "override_sis_stickiness"=>null,
			#                 "add_sis_stickiness"=>null,
			#                 "clear_sis_stickiness"=>null,
			#                 "diffing_data_set_identifier"=>null,
			#                 "diffed_against_import_id"=>null,
			#                 "processing_warnings"=>[["users.csv","No login_id given for user 67102976"],
			#                                         ["enrollments.csv","User 67102976 didn't exist for user enrollment"],
			#                                         ["enrollments.csv","User 67102976 didn't exist for user enrollment"],
			#                                         ["enrollments.csv","User 67102976 didn't exist for user enrollment"]]}

			# write the warning message into log file
			outputFile.write("upload process warning: #{parsed_result["processing_warnings"]}\n")
			# assign the warning message to upload_warnings param
			$upload_warnings = parsed_result["processing_warnings"]
		else
			outputFile.write("upload process finished successfully\n")
		end
	end

	# upload stop time
	outputFile.write("upload stop time : " + Time.new.inspect + "\n")

	return upload_error

end ## end of method definition

# get the prior upload process id and make Canvas API calls to see the current process status
# return true if the process is 100% finished; false otherwise
def prior_upload_error
	# find all the process id files, and sort in descending order based on last modified time
	id_log_file_path = "#{$currentDirectory}logs/*_id.txt"
	p "id log file path is #{id_log_file_path}"
	files = Dir.glob(id_log_file_path)
	files = files.sort_by { |file| File.mtime(file) }.reverse
	if (files.size == 0)
		p "no id file found in path #{id_log_file_path}"
		## first run, no prior cases
		return false
	else
		## get the first and most recent id file
		id_file = files[0]
		p "found recent id file #{id_file}"
		process_id = ''
		File.open(id_file, 'r') do |idFile|
			while line = idFile.gets
				# only read the first line, which is the token value
				process_id=line.strip
				break
			end
		end

		process_result = Canvas_API_GET("#{$server_api_url}accounts/#{ACCOUNT_NUMBER}/sis_imports/#{process_id}")
		p process_result
		if (process_result["errors"] && (process_result["errors"].is_a? Array))
			p "#{process_result["errors"][0]["message"]} for process id number #{process_id}. Continue with current upload."
			# if the prior process lookup result in error, there is no need to block future uploads
			return false
		end
		#parse the status percentage
		progress_status = process_result["progress"]
		if (progress_status != 100)
			# the prior job has not been processed 100%
			p "Prior upload process percent is #{process_id} has not finished yet. That progress status is #{progress_status}"
			return true
		else
			# prior job finished, ready for new upload
			return false
		end

		return true
	end
end

def verify_checksum(base_file_path)
	# default value
	upload_error = false

	# checksum verification
	checksum_file_names = Dir["#{base_file_path}MD5.txt"];
	if (checksum_file_names.length == 0)
		## there is no *MD5.txt file
		upload_error = "Cannot find checksum file #{base_file_path}MD5.txt."
	elsif (checksum_file_names.length > 1)
		## there are more than one checksum file
		upload_error = "There are more than one checksum file. "
	else
		## verify checksum value
		# 1.read checksum value from the *MD5.txt file
		checksum = ""
		File.open("#{base_file_path}MD5.txt", 'r') do |checksum_file|
			while line = checksum_file.gets
				# only read the first line, which is the checksum value
				checksum=line.strip
				break
			end
		end

		# 2. generate the checksum from current file
		new_checksum = Digest::MD5.hexdigest(File.read("#{base_file_path}.zip"))

		# 3. compare two checksum values
		if (!checksum.eql? new_checksum)
			upload_error = "Checksum value mismatch for #{base_file_path}.zip."
		end
	end

	# return error if any
	return upload_error
end

def get_settings(securityFile, propertiesFile)
	# 1. read from security file
	if (Dir[securityFile].length != 1)
		## security file
		return "Cannot find security file #{securityFile}."
	else
		File.open(securityFile, 'r') do |sFile|
			while line = sFile.gets
				# only read the first line
				# format: token=TOKEN,server=SERVER,directory=DIRECTORY
				env_array = line.strip.split(',')
				if (env_array.size != 2)
					return "security file should have the settings in format of: token=TOKEN,server=SERVER"
				end
				token_array=env_array[0].split('=')
				$token=token_array[1]
				server_array=env_array[1].split('=')
				$server=server_array[1]
				$server_api_url= "#{$server}#{API_PATH}"
				break
			end
		end
		if ($token=="")
			return "Empty token for Canvas upload."
		end
	end

	#2. read from properties file
	if (Dir[propertiesFile].length != 1)
		## properties file
		return "Cannot find properties file #{propertiesFile}."
	else
		File.open(propertiesFile, 'r') do |pFile|
			while line = pFile.gets
				# only read the first line
				# format: directory=DIRECTORY,sleep=SLEEP,alert_email_address=ALERT_EMAIL_ADDRESS,canvas_time_interval=INTERVAL_IN_SECONDS,canvas_allowed_call_number=NUMBER
				env_array = line.strip.split(',')
				if (env_array.size != 5)
					return "properties file should have the settings in format of: directory=DIRECTORY,sleep=SLEEP,alert_email_address=ALERT_EMAIL_ADDRESS,canvas_allowed_call_number=NUMBER"
				end
				directory_array=env_array[0].split('=')
				$currentDirectory=directory_array[1]
				sleep_array=env_array[1].split('=')
				$sleep=sleep_array[1].to_i
				alert_email_address_array=env_array[2].split('=')
				$alert_email_address=alert_email_address_array[1]
				p "alert email address = #{$alert_email_address}"
				canvas_interval_array=env_array[3].split('=')
				@Canvas_time_interval_in_seconds=canvas_interval_array[1].to_i
				canvas_call_array=env_array[4].split('=')
				@Canvas_allowed_call_number_during_interval=canvas_call_array[1].to_i
				break
			end
		end
		if (Dir[$currentDirectory].length != 1)
			## working directory
			return "Cannot find current working directory " + $currentDirectory + "."
		else
			# get the current working directory and the archive folder inside
			$archiveDirectory=$currentDirectory + "archive/"
			$outputDirectory=$currentDirectory + "logs/"

			p "server=" + $server
			p "current directory: " + $currentDirectory
			p "archive directory: " + $archiveDirectory
			p "output directory: " + $outputDirectory

			if (Dir[$archiveDirectory].length != 1)
				## archive directory
				return "Cannot find archive directory " + $archiveDirectory + "."
			end
			if (Dir[$outputDirectory].length != 1)
				## logs directory
				return "Cannot find output directory " + $outputDirectory + "."
			end
		end
	end

	# all is fine
	return false
end

#
# The function
#
def create_instructor_sandbox_site(zip_file_name, outputFile)
	# create a hash for all unique teachers SIS ids
	set_teacher_sis_ids = Set.new
	Zip::ZipFile.open(zip_file_name) do |zipfile|
		zipfile.each do |entry|
			if entry.name == ENROLLMENTS_FILE_NAME
				# read the enrollment file name
				user_line_content = entry.get_input_stream.read
				user_line_array = user_line_content.split("\n")
				user_line_array.each {
					|user|
					# format of ',user_mpathway_id,role,section_id,status'
					user_attrs = user.split(",")
					user_mpathway_id = user_attrs[1]
					user_role = user_attrs[2]
					user_status = user_attrs[4]
					if (TEACHER_ROLE_ARRAY.include? user_role and user_status == ACTIVE_STATUS)
						# find user with teacher role and is active
						if (!set_teacher_sis_ids.include? user_mpathway_id)
							set_teacher_sis_ids.add user_mpathway_id
							p "add user id = #{user_mpathway_id} into set"
						end
					end
				}
				p "found total #{set_teacher_sis_ids.size} users with teaching role"
				outputFile.write "\n\n found total #{set_teacher_sis_ids.size} users with teaching role \n\n"\

				# now that we have a set of newly added teacher sis ids, we will create sandbox site for those users

				# counter
				count_teachers = 0
				set_teacher_sis_ids.each {
					|user_mpathway_id|
					count_teachers = count_teachers+1
					p "#{count_teachers}/#{set_teacher_sis_ids.size} found user #{user_mpathway_id}"
					outputFile.write("#{count_teachers}/#{set_teacher_sis_ids.size} found user #{user_mpathway_id}")
					# find user canvas id
					user_details_json = Canvas_API_GET("#{$server_api_url}accounts/#{ACCOUNT_NUMBER}/users?search")
					user_canvas_id = user_details_json[0]["id"]
					user_sis_login_id = user_details_json[0]["sis_login_id"]
					user_sandbox_site_name = TARGET_USER_SANDBOX_NAME.gsub(USERNAME, user_sis_login_id)
					# see whether there is an sandbox site for this user
					previous_user_sandbox_site = Canvas_API_GET("#{$server_api_url}accounts/#{ACCOUNT_NUMBER}/courses?search_term=#{PREVIOUS_USER_SANDBOX_NAME.gsub(USERNAME, user_sis_login_id)}")
					if (previous_user_sandbox_site.length == 0)
						# check again for the current naming format of user sandbox site
						user_sandbox_site = Canvas_API_GET("#{$server_api_url}accounts/#{ACCOUNT_NUMBER}/courses?search_term=#{user_sandbox_site_name}")
						if (user_sandbox_site.length == 0)
							# if there is no such sandbox site, creat one
							result = Canvas_API_POST("#{$server_api_url}accounts/#{ACCOUNT_NUMBER}/courses",
							                         {
								                         "account_id"   => ACCOUNT_NUMBER,
								                         "course[name]" => user_sandbox_site_name,
								                         "course[course_code]" => user_sandbox_site_name
							                         })
							p result
							outputFile.write("Created a sandbox site - #{user_sandbox_site_name} for User #{user_sis_login_id} \n #{result} \n");

							if (result.has_key?("id"))
								# get the newly created course id
								# add the instructor to the course as instructor
								sandbox_course_id = result.fetch("id")
								instructor_result = Canvas_API_POST("#{$server_api_url}courses/#{sandbox_course_id}/enrollments",
								                                    {
									                                    "enrollment[user_id]"   => user_canvas_id,
									                                    "enrollment[type]" => "TeacherEnrollment",
									                                    "enrollment[enrollment_state]" => "active"
								                                    })
								p instructor_result
								outputFile.write("Enrolled User #{user_sis_login_id} to sandbox course site - #{user_sandbox_site_name} (#{sandbox_course_id}) \n #{instructor_result} \n");

							end
						end
					else
						# need to rename the previous course with new course title format
						course_id=previous_user_sandbox_site[0]["id"]
						# if there is no such sandbox site, creat one
						result = Canvas_API_PUT("#{$server_api_url}courses/#{course_id}",
						                         {
							                         "course[name]" => user_sandbox_site_name,
							                         "course[course_code]" => user_sandbox_site_name
						                         })
						outputFile.write("User #{user_sis_login_id} has a old sandbox site #{user_sandbox_site_name}, and it is renamed to new title #{user_sandbox_site_name}\n");
					end
				}
			end
		end
	end
end


# the command line argument count
count=1
# iterate through the inline arguments
ARGV.each do|arg|
	if (count==1)
		#security file
		securityFile = arg
	elsif (count==2)
		# the second argument should be the server name
		propertiesFile=arg
	else
		# break
	end

	#increase count
	count=count+1
end

# read the settings from properties files
upload_error = get_settings(securityFile, propertiesFile)

outputFile = false
if (!upload_error)
	#open the output file
	begin
		# get output file name
		output_file_base_name = "Canvas_upload_" + Time.new.strftime("%Y%m%d%H%M%S")
		outputFile = File.open($outputDirectory + output_file_base_name + ".txt", "w")

		# the canvas import zip file
		fileNames = Dir[$currentDirectory+ "Canvas_Extract_*.zip"];
		if (fileNames.length == 0)
			## cannot find zip file to upload
			upload_error = "Cannot find SIS zip file."
		elsif (fileNames.length > 1)
			## there are more than one zip file
			upload_error = "There are more than one SIS zip files to be uploaded."
		elsif
			## get the name of file to process
			fileName=fileNames[0]
			currentFileBaseName = File.basename(fileName, ".zip")

			## checksum verification step
			upload_error = verify_checksum($currentDirectory + currentFileBaseName)

			if (!upload_error)
				# upload the file to canvas server
				#upload_error = upload_to_canvas(fileName, outputFile, output_file_base_name)
			end

			## create sandbox sites for instructors newly uploaded
			## if they do not have such a site now
			create_instructor_sandbox_site($currentDirectory + currentFileBaseName + ".zip", outputFile)
		end
	end
end

if (upload_error)
	## check first about the environment variable setting for $alert_email_address '
	p "Sending out SIS upload error messages to #{$alert_email_address}"
	p upload_error
	## send email to support team with the error message
	`echo #{upload_error} | mail -s "#{$server} SIS Upload Error" #{$alert_email_address}`
else
	if ($upload_warnings != "")
		# mail the upload warning message
		## check first about the environment variable setting for $alert_email_address
		p "Sending out SIS upload warning messages to #{$alert_email_address}"
		p $upload_warnings
		## send email to support team with the error message
		`echo #{$upload_warnings}  | mail -s "#{$server} SIS Upload Warnings" #{$alert_email_address}`
	end

	# write the success message
	## if there is no upload error
	# move file to archive directory after processing
	FileUtils.mv(Dir.glob("#{$currentDirectory}*.zip"), $archiveDirectory)
	FileUtils.mv(Dir.glob("#{$currentDirectory}*MD5.txt"), $archiveDirectory)

	upload_success_msg = "SIS upload finished with " + fileName
	outputFile.write(upload_success_msg)
	p upload_success_msg
end

# close output file
outputFile.close unless outputFile == false
