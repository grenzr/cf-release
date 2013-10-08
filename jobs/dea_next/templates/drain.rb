#!/var/vcap/packages/ruby/bin/ruby --disable-all

require "logger"
require "fileutils"
require "json"

FileUtils.mkdir_p("/var/vcap/sys/log/dea_next")

job_change, hash_change, *updated_packages = ARGV

DEA_PIDFILE = "/var/vcap/sys/run/dea_next/dea_next.pid"
WARDEN_PIDFILE = "/var/vcap/sys/run/warden/warden.pid"
SNAPSHOT_PATH = "/var/vcap/data/dea_next/db/instances.json"

class DEADrainer
  def initialize(argv)
    @argv = argv
  end

  def drain
    logger.info("Drain script invoked with #{@argv.join(" ")}")

    unless dea_pid
      logger.info("DEA not running; not draining")
      set_timeout(0)
      return
    end

    unless warden_pid
      logger.info("Warden not running; not draining")
      set_timeout(0)
      return
    end

    job_change = @argv.first

    if job_change == "job_shutdown"
      evacuate
    elsif staging_tasks.empty?
      soft_shutdown
    else
      disable_dea
    end
  rescue => e
    logger.info("Failed to drain: #{e}")
    set_timeout(0)
  end

  private

  def evacuate
    logger.info("Sending signal USR2 to DEA to trigger evacuation.")
    Process.kill("USR2", dea_pid)

    set_timeout(120)
  end

  def soft_shutdown
    logger.info("Sending signal KILL to DEA.")
    Process.kill("KILL", dea_pid)

    logger.info("Sending signal USR2 to Warden to trigger draining.")
    Process.kill("USR2", warden_pid)

    set_timeout(0)
  end

  def disable_dea
    logger.info("Sending signal USR1 to DEA to take it out of placement pools.")
    Process.kill("USR1", dea_pid)

    set_timeout(-10)
  end

  def set_timeout(timeout)
    if timeout >= 0
      logger.info("Setting timeout to #{timeout}.")
    else
      logger.info("Telling agent to drain again in #{-timeout} seconds.")
    end

    puts timeout
  end

  def staging_tasks
    snapshot ? snapshot["staging_tasks"] : []
  end

  def snapshot
    @snapshot ||=
      if File.exists?(SNAPSHOT_PATH)
        JSON.load(File.open(SNAPSHOT_PATH))
      end
  end

  def dea_pid
    @dea_pid ||=
      if File.exists?(DEA_PIDFILE)
        File.read(DEA_PIDFILE).to_i
      end
  end

  def warden_pid
    @warden_pid ||=
      if File.exists?(WARDEN_PIDFILE)
        File.read(WARDEN_PIDFILE).to_i
      end
  end

  def logger
    @logger ||= Logger.new("/var/vcap/sys/log/dea_next/drain.log")
  end
end

DEADrainer.new(ARGV).drain
