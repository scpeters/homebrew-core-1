class Hbase < Formula
  desc "Hadoop database: a distributed, scalable, big data store"
  homepage "https://hbase.apache.org"
  url "https://www.apache.org/dyn/closer.cgi?path=hbase/1.2.6.1/hbase-1.2.6.1-bin.tar.gz"
  sha256 "3bfa55c0b2b1327cb4382c1a51dddd21a536ccbbfdbcc31e9b6f403fe21230ad"

  bottle do
    sha256 "ad2f8a6edee755254654904724c08c05bc9f05f82432b0b69022723624b13de8" => :mojave
    sha256 "3c4084898091f6b811062aff85f2d5dcef422d720b21e60b0554a24ac611e0d9" => :high_sierra
    sha256 "e2102bd08b2d94f5ac4d33938cdc76166bd085c9657f6f2ebcff47bbf3d3fd85" => :sierra
    sha256 "72240c500dda738b40241eba7c157bdcb4e1a5cdec79b85fb74cbccebb02bef3" => :el_capitan
  end

  depends_on :java => "1.8"
  depends_on "hadoop" => :optional
  depends_on "lzo"
  depends_on "ant" => :build
  depends_on :arch => :x86_64
  # 64 bit is required because of three things:
  # the lzo jar has a native extension
  # building native extensions requires a version of java that matches the architecture
  # there is no 32 bit version of java for macOS since Java 1.7, and 1.7+ is required for hbase
  depends_on "gcc" => :build unless OS.mac?

  resource "hadoop-lzo" do
    url "https://github.com/cloudera/hadoop-lzo/archive/0.4.14.tar.gz"
    sha256 "aa8ddbb8b3f9e1c4b8cc3523486acdb7841cd97c002a9f2959c5b320c7bb0e6c"
  end

  def install
    rm_f Dir["bin/*.cmd", "conf/*.cmd"]
    libexec.install %w[bin conf docs lib hbase-webapps]

    # Some binaries have really generic names (like `test`) and most seem to be
    # too special-purpose to be permanently available via PATH.
    %w[hbase start-hbase.sh stop-hbase.sh].each do |script|
      (bin/script).write_env_script "#{libexec}/bin/#{script}", Language::Java.java_home_env("1.8")
    end

    resource("hadoop-lzo").stage do
      # Fixed upstream: https://github.com/cloudera/hadoop-lzo/blob/master/build.xml#L235
      inreplace "build.xml",
                %r{(<class name="com.hadoop.compression.lzo.LzoDecompressor" />)},
                "\\1\n<classpath refid=\"classpath\"/>"
      ENV["CLASSPATH"] = Dir["#{libexec}/lib/hadoop-common-*.jar"].first
      ENV["CFLAGS"] = "-m64"
      ENV["CXXFLAGS"] = "-m64"
      ENV["CPPFLAGS"] = "-I#{OS.mac? ? "/System/Library/Frameworks/JavaVM.framework/Versions/Current/Headers" : Formula["jdk"].opt_include}"
      system "ant", "compile-native", "tar"
      (libexec/"lib").install Dir["build/hadoop-lzo-*/hadoop-lzo-*.jar"]
      (libexec/"lib/native").install Dir["build/hadoop-lzo-*/lib/native/*"]
    end

    inreplace "#{libexec}/conf/hbase-env.sh" do |s|
      # upstream bugs for ipv6 incompatibility:
      # https://issues.apache.org/jira/browse/HADOOP-8568
      # https://issues.apache.org/jira/browse/HADOOP-3619
      s.gsub!("export HBASE_OPTS=\"-XX:+UseConcMarkSweepGC\"",
              "export HBASE_OPTS=\"-Djava.net.preferIPv4Stack=true -XX:+UseConcMarkSweepGC\"")
      s.gsub!("# export JAVA_HOME=/usr/java/jdk1.6.0/",
              "export JAVA_HOME=\"$(/usr/libexec/java_home --version 1.8)\"")
      # avoid deprecated-option warning issued by Java 8
      s.gsub!(" -XX:PermSize=128m -XX:MaxPermSize=128m", "")

      # Default `$HBASE_HOME/logs` is unsuitable as it would cause writes to the
      # formula's prefix. Provide a better default but still allow override.
      s.gsub!(/^# export HBASE_LOG_DIR=.*$/,
              "export HBASE_LOG_DIR=\"${HBASE_LOG_DIR:-#{var}/log/hbase}\"")
    end

    # makes hbase usable out of the box
    # upstream has been provided this patch
    # https://issues.apache.org/jira/browse/HBASE-15426
    inreplace "#{libexec}/conf/hbase-site.xml",
      /<configuration>/,
      <<~EOS
        <configuration>
          <property>
            <name>hbase.rootdir</name>
            <value>#{build.with?("hadoop") ? "hdfs://localhost:9000" : "file://"+var}/hbase</value>
          </property>
          <property>
            <name>hbase.zookeeper.property.clientPort</name>
            <value>2181</value>
          </property>
          <property>
            <name>hbase.zookeeper.property.dataDir</name>
            <value>#{var}/zookeeper</value>
          </property>
          <property>
            <name>hbase.zookeeper.dns.interface</name>
            <value>lo0</value>
          </property>
          <property>
            <name>hbase.regionserver.dns.interface</name>
            <value>lo0</value>
          </property>
          <property>
            <name>hbase.master.dns.interface</name>
            <value>lo0</value>
          </property>
      EOS
  end

  def post_install
    (var/"log/hbase").mkpath
    (var/"run/hbase").mkpath
  end

  plist_options :manual => "#{HOMEBREW_PREFIX}/opt/hbase/bin/start-hbase.sh"

  def plist; <<~EOS
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>KeepAlive</key>
      #{build.without?("hadoop") ? "<true/>" : "<dict>\n        <key>OtherJobEnabled</key>\n        <string>"+Formula["hadoop"].plist_name+"</string>\n      </dict>"}
      <key>Label</key>
      <string>#{plist_name}</string>
      <key>EnvironmentVariables</key>
      <dict>
       <key>HBASE_MASTER_OPTS</key><string> -XX:PermSize=128m -XX:MaxPermSize=128m</string>
       <key>HBASE_LOG_DIR</key><string>#{var}/hbase</string>
       <key>HBASE_HOME</key><string>#{opt_libexec}</string>
       <key>HBASE_SECURITY_LOGGER</key><string>INFO,RFAS</string>
       <key>HBASE_PID_DIR</key><string>#{var}/run/hbase</string>
       <key>HBASE_NICENESS</key><string>0</string>
       <key>HBASE_IDENT_STRING</key><string>root</string>
       <key>HBASE_REGIONSERVER_OPTS</key><string> -XX:PermSize=128m -XX:MaxPermSize=128m</string>
       <key>HBASE_OPTS</key><string>-XX:+UseConcMarkSweepGC</string>
       <key>HBASE_ROOT_LOGGER</key><string>INFO,RFA</string>
       <key>HBASE_LOG_PREFIX</key><string>hbase-root-master</string>
       <key>HBASE_LOGFILE</key><string>hbase-root-master.log</string>
      </dict>
      <key>ProgramArguments</key>
      <array>
        <string>#{opt_bin}/hbase</string>
        <string>--config</string>
        <string>#{opt_libexec}/conf</string>
        <string>master</string>
        <string>start</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>WorkingDirectory</key>
      <string>#{HOMEBREW_PREFIX}</string>
      <key>StandardOutPath</key>
      <string>#{var}/hbase/hbase.log</string>
      <key>StandardErrorPath</key>
      <string>#{var}/hbase/hbase.err</string>
    </dict>
    </plist>
  EOS
  end

  test do
    assert_match "HBase #{version}", shell_output("#{bin}/hbase version 2>&1")

    cp_r (libexec/"conf"), testpath
    inreplace (testpath/"conf/hbase-site.xml") do |s|
      s.gsub! /(hbase.rootdir.*)\n.*/, "\\1\n<value>file://#{testpath}/hbase</value>"
      s.gsub! /(hbase.zookeeper.property.dataDir.*)\n.*/, "\\1\n<value>#{testpath}/zookeeper</value>"
    end

    ENV["HBASE_LOG_DIR"]  = testpath/"logs"
    ENV["HBASE_CONF_DIR"] = testpath/"conf"
    ENV["HBASE_PID_DIR"]  = testpath/"pid"

    system "#{bin}/start-hbase.sh"
    sleep 10
    begin
      assert_match "Zookeeper", pipe_output("nc 127.0.0.1 2181 2>&1", "stats")
    ensure
      system "#{bin}/stop-hbase.sh"
    end
  end
end
