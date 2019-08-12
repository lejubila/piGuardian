# piGarden

Bash script to turn your Raspberry Pi into an anti-theft system

## License

This script is open-sourced software under GNU GENERAL PUBLIC LICENSE Version 3

## Installation to Raspbian Jessie

1) Installs the necessary packages on your terminal:

``` bash
sudo apt-get install git gzip wc tr cut grep ucspi-tcp mosquitto-clients
```

2) Compile and install gpio program from WiringPi package:

``` bash
cd
git clone git://git.drogon.net/wiringPi
cd wiringPi
git pull origin 
./build
```

3) Download and install piGuardian in your home

``` bash
cd
git clone https://github.com/lejubila/piGuardian.git
```

## Configuration

Copy configuration file in /etc

```bash
cd
sudo cp piGarden/conf/piGuardian.conf.example /etc/piGuardian.conf
```

Customize the configuration file. 
For more information see 
[www.lejubila.net/2015/12/impianto-di-irrigazione-con-raspberry-pi-pigarden-lo-script-di-gestione-quinta-parte/](https://www.lejubila.net/2015/12/impianto-di-irrigazione-con-raspberry-pi-pigarden-lo-script-di-gestione-quinta-parte/)
