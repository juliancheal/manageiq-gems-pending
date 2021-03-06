require "util/postgres_admin"

describe PostgresAdmin do
  context "ENV dependent" do
    after do
      ENV.delete_if { |k, _| k.start_with?("APPLIANCE") }
    end

    [%w(data_directory     APPLIANCE_PG_DATA            /some/path      true),
     %w(service_name       APPLIANCE_PG_SERVICE         postgresql          ),
     %w(package_name       APPLIANCE_PG_PACKAGE_NAME    postgresql-server   ),
     %w(template_directory APPLIANCE_TEMPLATE_DIRECTORY /some/path      true),
     %w(mount_point        APPLIANCE_PG_MOUNT_POINT     /mount/point    true)
    ].each do |method, var, value, pathname_required|
      it method.to_s do
        ENV[var] = value
        result = described_class.public_send(method)
        if pathname_required
          expect(result.join("abc/def").to_s).to eql "#{value}/abc/def"
        else
          expect(result).to eql value
        end
      end
    end

    it ".logical_volume_path" do
      expect(described_class.logical_volume_path.to_s).to eql "/dev/vg_data/lv_pg"
    end

    context "with a data directory" do
      around do |example|
        Dir.mktmpdir do |dir|
          ENV["APPLIANCE_PG_DATA"] = dir
          example.run
        end
      end

      describe ".initialized?" do
        it "returns true with files in the data directory" do
          FileUtils.touch("#{ENV["APPLIANCE_PG_DATA"]}/somefile")
          expect(described_class.initialized?).to be true
        end

        it "returns false without files in the data directory" do
          expect(described_class.initialized?).to be false
        end
      end

      describe ".local_server_in_recovery?" do
        it "returns true when recovery.conf exists" do
          FileUtils.touch("#{ENV["APPLIANCE_PG_DATA"]}/recovery.conf")
          expect(described_class.local_server_in_recovery?).to be true
        end

        it "returns false when recovery.conf does not exist" do
          expect(described_class.local_server_in_recovery?).to be false
        end
      end

      describe ".local_server_status" do
        let(:service) { double("postgres service") }

        before do
          ENV["APPLIANCE_PG_SERVICE"] = "postgresql"
          allow(LinuxAdmin::Service).to receive(:new).and_return(service)
        end

        context "when the server is running" do
          before do
            allow(service).to receive(:running?).and_return(true)
          end

          it "returns a running status and primary with no recovery file" do
            expect(described_class.local_server_status).to eq("running (primary)")
          end

          it "returns a running status and standby with a recovery file" do
            FileUtils.touch("#{ENV["APPLIANCE_PG_DATA"]}/recovery.conf")
            expect(described_class.local_server_status).to eq("running (standby)")
          end
        end

        context "when the server is not running" do
          before do
            allow(service).to receive(:running?).and_return(false)
          end

          it "returns initialized and stopped if it is initialized" do
            FileUtils.touch("#{ENV["APPLIANCE_PG_DATA"]}/somefile")
            expect(described_class.local_server_status).to eq("initialized and stopped")
          end

          it "returns not initialized if the data directory is empty" do
            expect(described_class.local_server_status).to eq("not initialized")
          end
        end
      end
    end
  end
end
