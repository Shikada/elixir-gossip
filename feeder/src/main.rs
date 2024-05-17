use std::ffi::OsStr;
use std::fs::remove_file;
use std::io::{stdin, stdout, BufRead, Write};
use std::os::unix::net::UnixDatagram;
use std::path::Path;
use std::thread;

use rand::distributions::{Alphanumeric, DistString};
use glob::glob;

// use regex::Regex;

fn main() -> anyhow::Result<()> {
    // let init_regex = Regex::new(r#""node_id":\s+"(.+)""#).expect("Tried to create invalid regex for init message");
    let random_feeder_name = Alphanumeric.sample_string(&mut rand::thread_rng(), 8);
    let feeder_in_path_string = format!("/tmp/feeder-in-{random_feeder_name}.sock");
    let feeder_in_path = Path::new(OsStr::new(&feeder_in_path_string));
    let feeder_out_path_string = format!("/tmp/feeder-out-{random_feeder_name}.sock");
    let feeder_out_path = Path::new(OsStr::new(&feeder_out_path_string));
    let echo_path = Path::new("/tmp/echo.sock");

    for path in glob("/tmp/feeder-*.sock").expect("Failed glob pattern") {
        remove_file(path.unwrap()).expect("Failed to delete feeder socket file");
    }

    if echo_path.exists() {
        remove_file(echo_path)?;
    }

    let feeder_in_sock = UnixDatagram::bind(feeder_in_path)?;
    let feeder_out_sock = UnixDatagram::bind(feeder_out_path)?;
    // let echo_sock = UnixDatagram::bind(echo_path)?;

    let feeder_out_thread_handle = thread::spawn(move || {
        feeder_out_sock.connect(echo_path).unwrap();
        let stdin = stdin().lock();
        let mut line_iterator = stdin.lines();
        let first_line = line_iterator
            .next()
            .unwrap()
            .expect("Error while reading line from stdin");

        if first_line.contains(r#""init""#) {
            feeder_out_sock.send(first_line.as_bytes()).unwrap();
        } else {
            panic!("Expected first message from stdin to be an 'init' message, but wasn't.");
        }

        for line in line_iterator {
            feeder_out_sock.send(line.unwrap().as_bytes()).unwrap();
        }
    });

    let feeder_in_thread_handle = thread::spawn(move || {
        // let echo_sock = UnixDatagram::bind(echo_path).unwrap();
        let mut stdout = stdout().lock();
        let mut buffer = [0; 2048];

        loop {
            // let (rec_size, rec_addr) = echo_sock.recv_from(buffer.as_mut_slice()).unwrap();
            // let result = str::from_utf8(&buffer[0..rec_size]).unwrap();
            // let rec_path = rec_addr.as_pathname().unwrap().display();
            // println!("received {rec_size} bytes from {rec_path}");
            // println!("got '{result}' from socket");
            let rec_size = feeder_in_sock.recv(buffer.as_mut_slice()).unwrap();
            stdout.write_all(&buffer[0..rec_size]).expect("Failed to write received message from socket to stdout");
            stdout.write_all(b"\n").expect("Failed to write trailing newline to stdout");
            stdout.flush().unwrap();
        }
    });

    feeder_out_thread_handle.join().unwrap();
    feeder_in_thread_handle.join().unwrap();

    Ok(())
}
