# Replaces the Solid Queue recurring task that used to live in
# config/recurring.yml (see that file and config/puma.rb for why Solid Queue
# isn't usable here). The app is already single-instance/single-process per
# Empresa.para_esta_instancia (see CLAUDE.md), so a plain in-process loop
# reproduces the old "every minute" cadence without needing a jobs table.
#
# `defined?(Rails::Server)` is only true when booted via `rails server` (i.e.
# Puma), so this doesn't fire during `rails db:prepare`, `assets:precompile`,
# rake tasks, or the console.
if Rails.env.production? && defined?(Rails::Server)
  Thread.new do
    loop do
      sleep 60
      begin
        EnvioAutomaticoAtosJob.perform_now
      rescue => e
        Rails.logger.error("[EnvioAutomaticoScheduler] #{e.class}: #{e.message}")
      end
    end
  end
end
