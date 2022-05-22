class Logger
  # Initialize a Logger instance.
  # @param [Boolean] verbose
  # @param [String] export_logs_path
  def initialize(verbose: false, export_logs_path: nil)
    @verbose = verbose
    @export_logs_path = export_logs_path
  end

  def log(message, force_verbose: false)
    return unless force_verbose || @verbose
    puts message

    return unless @export_logs_path
    File.open(@export_logs_path, "a") { |f| f.write("#{message}\n") }  
  end
end
