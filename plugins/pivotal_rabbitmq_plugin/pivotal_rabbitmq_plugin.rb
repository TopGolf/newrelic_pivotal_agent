#! /usr/bin/env ruby
#
# The MIT License
#
# Copyright (c) 2013-2014 Pivotal Software, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#


require 'rubygems'
require 'bundler/setup'
require 'newrelic_plugin'
require 'rabbitmq_manager'
require 'uri'

module NewRelic
  $venue = ENV["VENUE_NAME"]
  module RabbitMQPlugin
    class Agent < NewRelic::Plugin::Agent::Base
      agent_guid 'com.pivotal.newrelic.plugin.rabbitmq.topgolf'
      agent_version '1.0.5'
      agent_config_options :management_api_url, :debug
      agent_human_labels('Topgolf') do
        uri = URI.parse(management_api_url)
        "#{uri.host}:#{uri.port}"
      end

      def poll_cycle
        begin
          if "#{self.debug}" == "true" 
            puts "[RabbitMQ] Debug Mode On: Metric data will not be sent to new relic"
          end

          report_metric_check_debug 'Queued Messages/Ready' + $venue, 'messages', queue_size_ready
          report_metric_check_debug 'Queued Messages/Unacknowledged' + $venue, 'messages', queue_size_unacknowledged

          report_metric_check_debug 'Message Rate/Acknowledge' + $venue, 'messages/sec', ack_rate
          report_metric_check_debug 'Message Rate/Confirm' + $venue, 'messages/sec', confirm_rate
          report_metric_check_debug 'Message Rate/Deliver' + $venue, 'messages/sec', deliver_rate
          report_metric_check_debug 'Message Rate/Publish' + $venue, 'messages/sec', publish_rate
          report_metric_check_debug 'Message Rate/Return' + $venue, 'messages/sec', return_unroutable_rate

          report_metric_check_debug 'Node/File Descriptors' + $venue, 'file_descriptors', node_info('fd_used')
          report_metric_check_debug 'Node/Sockets' + $venue , 'sockets', node_info('sockets_used')
          report_metric_check_debug 'Node/Erlang Processes' + $venue, 'processes', node_info('proc_used')
          report_metric_check_debug 'Node/Memory Used' + $venue, 'bytes', node_info('mem_used')

          report_queues

          report_exchanges

          report_exchanges_bindings_source

        rescue Exception => e
          $stderr.puts "[RabbitMQ] Exception while processing metrics. Check configuration."
          $stderr.puts e.message  
          if "#{self.debug}" == "true"
            $stderr.puts e.backtrace.inspect
          end
        end
      end

      def report_metric_check_debug(metricname, metrictype, metricvalue)
        if "#{self.debug}" == "true"
          puts("#{metricname}[#{metrictype}] : #{metricvalue}")
        else
          report_metric metricname, metrictype, metricvalue
        end
      end
      private
      def rmq_manager
        @rmq_manager ||= ::RabbitMQManager.new(management_api_url)
      end

      #
      # Queue size
      #
      def queue_size_for(type = nil)
        totals_key = 'messages'
        totals_key << "_#{type}" if type

        queue_totals = rmq_manager.overview['queue_totals']
        if queue_totals.size == 0
          $stderr.puts "[RabbitMQ] No data found for queue_totals[#{totals_key}]. Check that queues are declared. No data will be reported."
        else
          queue_totals[totals_key] || 0
        end
      end

      def queue_size_ready
        queue_size_for 'ready'
      end

      def queue_size_unacknowledged
        queue_size_for 'unacknowledged'
      end

      #
      # Rates
      #
      def ack_rate
        rate_for 'ack'
      end

      def confirm_rate
        rate_for 'confirm'
      end

      def deliver_rate
        rate_for 'deliver'
      end

      def publish_rate
        rate_for 'publish'
      end

      def rate_for(type)
        msg_stats = rmq_manager.overview['message_stats']

        if msg_stats.is_a?(Hash)
          details = msg_stats["#{type}_details"]
          details ? details['rate'] : 0
        else
          0
        end
      end

      def return_unroutable_rate
        rate_for 'return_unroutable'
      end

      #
      # Node info
      #
      def node_info(key)
        default_node_name = rmq_manager.overview['node']
        node = rmq_manager.node(default_node_name)
        node[key]
      end

      def user_count
        rmq_manager.users.length
      end

      def report_queues
        return unless rmq_manager.queues.length > 0
        rmq_manager.queues.each do |q|
          next if q['name'].start_with?('amq.gen')
          report_metric_check_debug 'Queue' + q['vhost'] + q['name'] + '/Messages/Ready' + $venue, 'message', q['messages_ready']
          report_metric_check_debug 'Queue' + q['vhost'] + q['name'] + '/Memory' + $venue, 'bytes', q['memory']
          report_metric_check_debug 'Queue' + q['vhost'] + q['name'] + '/Messages/Total' + $venue, 'message', q['messages']
          report_metric_check_debug 'Queue' + q['vhost'] + q['name'] + '/Consumers/Total' + $venue, 'consumers', q['consumers']
          report_metric_check_debug 'Queue' + q['vhost'] + q['name'] + '/Consumers/Active' + $venue, 'consumers', q['active_consumers']
        end
      end

      def publish_in_rate
        exchange_rate_for 'in'
      end

      def publish_out_rate
        exchange_rate_for 'out'
      end

      def exchange_rate_for(type)
        msg_stats = rmq_manager.exchange['message_stats']

        if msg_stats_.is_a?(Hash)
          details = msg_stats["#{type}_details"]
          details ? details ['rate'] : 0
        else
          0
        end
      end

      def report_exchanges
        return unless rmq_manager.exchanges.length > 0
        rmq_manager.exchanges.each do |e|
          next if e['name'].start_with?('amq')
          next if e['name'] == ''
          puts "report_exchanges:"
          puts e
          puts e['message_stats']
          puts e['message_stats']['publish_in_details']
          puts e['message_stats']['publish_in_details']['rate']
          report_metric_check_debug 'Exchange' + e['vhost'] + e['name'] + '/Exchanges/In' + $venue, 'messages/sec', e['message_stats']['publish_in_details']['rate']
          report_metric_check_debug 'Exchange' + e['vhost'] + e['name'] + '/Exchanges/Out' + $venue, 'messages/sec', e['message_stats']['publish_out_details']['rate']
          report_metric_check_debug 'Exchange' + e['vhost'] + e['name'] + '/Messages/Total' + $venue, 'messages', e['message_stats']['publish_out']
          report_metric_check_debug 'Exchange' + e['vhost'] + e['name'] + '/Exchanges/Out' + $venue, 'messages/sec', e['message_stats']['publish_out_details']['rate']
        end
      end

      def report_exchanges_bindings_source
        return unless rmq_manager.exchanges.length > 0
        rmq_manager.exchanges.each do |e|
          next if e['name'].start_with?('amq')
          next if e['name'] == ''
          puts "report_exchanges_bindings_source"
          puts "**** GETTING QUEUES ****"
          puts e['vhost']
          puts e['name']
          body = rmq_manager.exchanges_bindings_source e['vhost'], e['name']
          puts "***** GOT EM!! *******"
          puts body.length
          report_metric_check_debug 'Exchange'+ e['vhost'] + e['name'] + 'Queues/Total' + $venue, 'queues/exchange', body.length
        end
      end

    end

    NewRelic::Plugin::Setup.install_agent :rabbitmq, self

    #
    # Launch the agent; this never returns.
    #
    if __FILE__==$0
      NewRelic::Plugin::Run.setup_and_run
    end
  end
end