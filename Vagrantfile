script = "
sudo yum install -y make
sudo yum install -y cmake
sudo yum install -y zlib-devel
sudo yum install -y glew-devel
sudo yum install -y freetype-devel
sudo yum install -y libvorbis
sudo yum install -y libvorbis-devel
sudo yum install -y libogg-devel
sudo yum install -y openal-soft-devel
sudo yum install -y bzip2-devel
sudo yum install -y libXrandr-devel
sudo yum install -y gcc
sudo yum install -y gcc-c++
sudo yum install -y libpng-devel
sudo yum install -y libcurl-devel
sudo yum install -y libXi-devel
echo 'To build:
    cd /vagrant && make -f source/linux/Makefile compile

After building, run the game with `bash StarRuler2.sh`' > /etc/motd
"

Vagrant.configure("2") do |config|
  config.vm.synced_folder ".", "/vagrant"

  config.vm.define "fedora-build" do |node|
    node.vm.box = "generic/fedora28"
    node.vm.provision "shell", inline: script
  end
end
