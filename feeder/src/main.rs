use std::fs::remove_file;
use std::io::stdin;
use std::io::BufRead;
use std::os::unix::net::UnixDatagram;
use std::path::Path;
use std::str;
use std::thread;

fn main() -> anyhow::Result<()> {
    let feeder_path = Path::new("/tmp/feeder.sock");
    let echo_path = Path::new("/tmp/echo.sock");

    if feeder_path.exists() {
        remove_file(feeder_path)?;
    }

    if echo_path.exists() {
        remove_file(echo_path)?;
    }

    let feeder_sock = UnixDatagram::bind(feeder_path)?;
    let echo_sock = UnixDatagram::bind(echo_path)?;
    // feeder_sock.connect(echo_sock.local_addr()?.as_pathname().unwrap())?;
    // feeder_sock.send(b"some fuckin data")?;
    // let mut buffer = [0; 2048];
    // let (rec_size, rec_addr) = echo_sock.recv_from(buffer.as_mut_slice())?;
    // let result = str::from_utf8(&buffer[0..rec_size])?;
    // let rec_path = rec_addr.as_pathname().unwrap().display();
    // println!("received {rec_size} bytes from {rec_path}");
    // println!("got '{result}' from socket");
    // feeder_sock.shutdown(std::net::Shutdown::Both)?;
    // echo_sock.shutdown(std::net::Shutdown::Both)?;

    let feeder_thread_handle = thread::spawn(move || {
        // let feeder_sock = UnixDatagram::bind(feeder_path).unwrap();
        feeder_sock.connect(echo_path).unwrap();
        let stdin = stdin().lock();

        for line in stdin.lines() {
            feeder_sock.send(line.unwrap().as_bytes()).unwrap();
        }
    });

    let echo_thread_handle = thread::spawn(move || {
        // let echo_sock = UnixDatagram::bind(echo_path).unwrap();
        let mut buffer = [0; 2048];

        loop {
            let (rec_size, rec_addr) = echo_sock.recv_from(buffer.as_mut_slice()).unwrap();
            let result = str::from_utf8(&buffer[0..rec_size]).unwrap();
            let rec_path = rec_addr.as_pathname().unwrap().display();

            println!("received {rec_size} bytes from {rec_path}");
            println!("got '{result}' from socket");
        }
    });

    feeder_thread_handle.join().unwrap();
    echo_thread_handle.join().unwrap();

    Ok(())
}
