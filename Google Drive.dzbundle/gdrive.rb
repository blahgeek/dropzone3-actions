require 'lib/google/api_client'
require 'lib/google/api_client/auth/file_storage'
require 'lib/google/api_client/auth/installed_app'
class Gdrive
  API_VERSION = 'v2'
  CACHED_API_FILE = "drive-#{API_VERSION}.cache"
  CREDENTIAL_STORE_FILE = "#{$0}-oauth2.json"
  Folder = Struct.new(:title, :folder_id)

  def configure_client
    $dz.begin('Connecting to Google Drive...')
    @client = Google::APIClient.new(:application_name => 'Dropzone 3 action for Google Drive',
                                    :application_version => '1.0.0')


    file_storage = Google::APIClient::FileStorage.new(CREDENTIAL_STORE_FILE)

    if file_storage.authorization.nil?
      flow = Google::APIClient::InstalledAppFlow.new(
          :client_id => ENV['username'],
          :client_secret => ENV['api_key'],
          :scope => ['https://www.googleapis.com/auth/drive']
      )

      @client.authorization = flow.authorize(file_storage)
    else
      @client.authorization = file_storage.authorization
    end

    @drive = nil
    if File.exists? CACHED_API_FILE
      File.open(CACHED_API_FILE) do |file|
        @drive = Marshal.load(file)
      end
    else
      @drive = @client.discovered_api('drive', API_VERSION)
      File.open(CACHED_API_FILE, 'w') do |file|
        Marshal.dump(@drive, file)
      end
    end

  end

  def upload_file (file_path, folder_id)
    file_name = file_path.split(File::SEPARATOR).last
    $dz.begin("Uploading #{file_name} to Google Drive...")
    content_type = `file -Ib #{file_path}`.gsub(/\n/, "")


    file = @drive.files.insert.request_schema.new({
                                                      :title => file_name,
                                                      :mimeType => content_type,
                                                      :parents => [{:id => folder_id}]
                                                  })

    media = Google::APIClient::UploadIO.new(file_path, content_type)
    result = @client.execute(
        :api_method => @drive.files.insert,
        :body_object => file,
        :media => media,
        :parameters => {
            :uploadType => 'multipart',
            :alt => 'json'
        })

    unless result.success?
      $dz.error(result.error_message)
    end
  end

  def get_folders
    result = @client.execute(
        :api_method => @drive.files.list,
        :parameters => {
            :q => "'root' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
        })

    # using an array and a struct to guarantee order
    folders = Array.new
    result.data['items'].each { |item|
      folders << Folder.new(item['title'], item['id'])
    }

    folders
  end

  def select_folder
    $dz.begin('What folder would you like to use?')
    folders = get_folders

    if folders.empty?
      folder_id = read_folder
    else
      folder_names = ''

      # check if there was a previously selected folder and if it's still in the folder list
      saved_folder_name = ENV['folder_name']
      index_saved_folder_name = folders.index { |x| x.title == saved_folder_name }
      no_saved_folder = (saved_folder_name.nil? or saved_folder_name.to_s.strip.length == 0 or index_saved_folder_name.nil? )

      # if there's a valid saved folder, then display it first and reorder array
      unless no_saved_folder
        folder_names = "#{folder_names} \"#{saved_folder_name}\" "
        folders.insert(0, folders.delete_at(index_saved_folder_name))
      end

      # arrange the list of folders, don't display the saved folder name again
      folders.each do |folder|
        unless !no_saved_folder and saved_folder_name == folder.title
          folder_names = "#{folder_names} \"#{folder.title}\" "
        end
      end

      output = $dz.cocoa_dialog("dropdown --button1 \"OK\" --button2 \"Cancel\"  --button3 \"New folder\" --title \"Select a folder\" --text \"In which folder would like to upload the file(s)?\" --items #{folder_names}")
      button, folder_index = output.split("\n")

      if button == '2'
        $dz.fail('Cancelled')
      end

      # if the user wants to create a new folder, or use one of the existing ones
      if button == '3'
        folder_id = read_folder
      else
        folder_index_int = Integer(folder_index)
        selected_folder = folders[folder_index_int]
        $dz.save_value('folder_name', selected_folder.title)
        folder_id = selected_folder.folder_id
      end
    end

    folder_id
  end

  def read_folder
    output = $dz.cocoa_dialog("standard-inputbox --button1 \"OK\" --button2 \"Cancel\" --title \"Create new folder\" --informative-text \"Enter the name of the new folder, where the file(s) will be uploaded:\"")
    button, folder_name = output.split("\n")

    if button == '2'
      $dz.fail('Cancelled')
    end

    if folder_name.to_s.strip.length == 0
      $dz.fail('You need to choose a folder!')
    end

    folder_id = create_new_folder(folder_name)
    $dz.save_value('folder_name', folder_name)

    folder_id
  end

  def create_new_folder(folder_name)
    $dz.begin("Creating new folder #{folder_name}...")
    content_type = 'application/vnd.google-apps.folder'

    file = @drive.files.insert.request_schema.new({
                                                      :title => folder_name,
                                                      :mimeType => content_type
                                                  })
    result = @client.execute(
        :api_method => @drive.files.insert,
        :body_object => file
    )

    unless result.success?
      $dz.error(result.error_message)
    end

    result.data['id']
  end
end