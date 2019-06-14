module HealthModel
    class HealthMonitorProvider

        attr_accessor :cluster_labels, :health_kubernetes_resources, :monitor_configuration_path
        attr_reader :monitor_configuration

        def initialize(cluster_labels, health_kubernetes_resources, monitor_configuration_path)
            @cluster_labels = Hash.new
            cluster_labels.each{|k,v| @cluster_labels[k] = v}
            @health_kubernetes_resources = health_kubernetes_resources
            @monitor_configuration_path = monitor_configuration_path
            begin
                @monitor_configuration = {}
                file = File.open(@monitor_configuration_path, "r")
                if !file.nil?
                    fileContents = file.read
                    @monitor_configuration = JSON.parse(fileContents)
                    file.close
                end
            rescue => e
                @log.info "Error when opening health config file #{e}"
            end
        end

        def get_record(health_monitor_record, health_monitor_state)

            labels = Hash.new
            @cluster_labels.each{|k,v| labels[k] = v}
            monitor_id = health_monitor_record.monitor_id
            monitor_instance_id = health_monitor_record.monitor_instance_id
            health_monitor_instance_state = health_monitor_state.get_state(monitor_instance_id)


            monitor_labels = health_monitor_record.labels
            if !monitor_labels.empty?
                monitor_labels.keys.each do |key|
                    labels[key] = monitor_labels[key]
                end
            end

            prev_records = health_monitor_instance_state.prev_records
            time_first_observed = health_monitor_instance_state.state_change_time # the oldest collection time
            new_state = health_monitor_instance_state.new_state # this is updated before formatRecord is called
            old_state = health_monitor_instance_state.old_state

            config = get_config(monitor_id)

            if prev_records.size == 1
                details = prev_records[0]
            else
                details = prev_records
            end

            time_observed = Time.now.utc.iso8601

            monitor_record = {}
            monitor_record[HealthMonitorRecordFields::CLUSTER_ID] = 'fake_cluster_id' #KubernetesApiClient.getClusterId
            monitor_record[HealthMonitorRecordFields::MONITOR_LABELS] = labels.to_json
            monitor_record[HealthMonitorRecordFields::MONITOR_ID] = monitor_id
            monitor_record[HealthMonitorRecordFields::MONITOR_INSTANCE_ID] = monitor_instance_id
            monitor_record[HealthMonitorRecordFields::NEW_STATE] = new_state
            monitor_record[HealthMonitorRecordFields::OLD_STATE] = old_state
            monitor_record[HealthMonitorRecordFields::DETAILS] = details
            monitor_record[HealthMonitorRecordFields::MONITOR_CONFIG] = config.to_json
            monitor_record[HealthMonitorRecordFields::AGENT_COLLECTION_TIME] = Time.now.utc.iso8601
            monitor_record[HealthMonitorRecordFields::TIME_FIRST_OBSERVED] = time_first_observed

            return monitor_record
        end

        def get_config(monitor_id)
            if @monitor_configuration.key?(monitor_id)
                return @monitor_configuration[monitor_id]
            else
                return {}
            end
        end

        def get_labels(health_monitor_record)
            monitor_labels = {}
            monitor_id = health_monitor_record[HealthMonitorRecordFields::MONITOR_ID]
            case monitor_id
            when HealthMonitorConstants::CONTAINER_CPU_MONITOR_ID, HealthMonitorConstants::CONTAINER_MEMORY_MONITOR_ID, HealthMonitorConstants::USER_WORKLOAD_PODS_READY_MONITOR_ID, HealthMonitorConstants::SYSTEM_WORKLOAD_PODS_READY_MONITOR_ID

                namespace = health_monitor_record[HealthMonitorRecordFields::DETAILS]['details']['namespace']
                workload_name = health_monitor_record[HealthMonitorRecordFields::DETAILS]['details']['workloadName']
                workload_kind = health_monitor_record[HealthMonitorRecordFields::DETAILS]['details']['workloadKind']

                monitor_labels['container.azm.ms/workload-name'] = workload_name.split('~~')[1]
                monitor_labels['container.azm.ms/workload-kind'] = workload_kind
                monitor_labels['container.azm.ms/namespace'] = namespace

            when HealthMonitorConstants::NODE_CPU_MONITOR_ID, HealthMonitorConstants::NODE_MEMORY_MONITOR_ID, HealthMonitorConstants::NODE_CONDITION_MONITOR_ID
                node_name = health_monitor_record[HealthMonitorRecordFields::NODE_NAME]
                @health_kubernetes_resources.get_node_inventory['items'].each do |node|
                    if !node_name.nil? && !node['metadata']['name'].nil? && node_name == node['metadata']['name']
                        if !node["metadata"].nil? && !node["metadata"]["labels"].nil?
                            monitor_labels = node["metadata"]["labels"]
                        end
                    end
                end
            end
            return monitor_labels
        end
    end
end