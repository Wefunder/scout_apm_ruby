module ScoutApm
  module BackgroundJobIntegrations
    class GoodJob
      attr_reader :logger

      def initialize(logger)
        @logger = logger
      end

      def name
        :good_job
      end

      def forking?
        false
      end

      def install
        require 'good_job'
        GoodJob::ActiveRecordParentClass.class_eval do
          include ScoutApm::Tracer

          around_perform do |job, block|
            # I have a sneaking suspicion there is a better way to handle Agent starting
            # Maybe hook into GoodJob lifecycle events?
            ScoutApm::Agent.instance.start_background_worker unless ScoutApm::Agent.instance.background_worker_running?
            req = ScoutApm::RequestManager.lookup
            latency = Time.now - job.scheduled_at rescue 0
            req.annotate_request(queue_latency: latency)

            begin
              req.start_layer ScoutApm::Layer.new("Queue", job.queue_name)
              started_queue = true # Following Convention
              req.start_layer ScoutApm::Layer.new("Job", job.job_class)
              started_job = true # Following Convention

              block.call
            rescue
              req.error!
              raise
            ensure
              req.stop_layer if started_job
              req.stop_layer if started_queue
            end
          end
        end
      end
    end
  end
end
