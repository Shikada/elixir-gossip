use std::ffi::OsStr;
use std::io::{stdin, stdout, BufRead, Write};
use std::os::unix::net::UnixDatagram;
use std::path::Path;
use std::sync::mpsc::{self, Receiver, Sender};
use std::{panic, process, thread};

use rand::distributions::{Alphanumeric, DistString};

// use regex::Regex;

fn main() -> anyhow::Result<()> {
    // let init_regex = Regex::new(r#""node_id":\s+"(.+)""#).expect("Tried to create invalid regex for init message");
    let random_feeder_name = Alphanumeric.sample_string(&mut rand::thread_rng(), 8);
    let feeder_in_path_string = format!("/tmp/echo/feeder-in-{random_feeder_name}.sock");
    let feeder_in_path = Path::new(OsStr::new(&feeder_in_path_string));
    let feeder_out_path_string = format!("/tmp/echo/feeder-out-{random_feeder_name}.sock");
    let feeder_out_path = Path::new(OsStr::new(&feeder_out_path_string));
    let node_path_string: &mut str = format!("/tmp/echo/node-{random_feeder_name}.sock").leak();
    //let node_path_string: &'static str = format!("/tmp/echo/node-{random_feeder_name}.sock");
    let node_path = Path::new(OsStr::new(node_path_string));
    let echo_path = Path::new("/tmp/echo/echo.sock");

    // for path in glob("/tmp/feeder-*.sock").expect("Failed glob pattern") {
    //     //remove_file(path.unwrap()).expect("Failed to delete feeder socket file");
    //     match remove_file(path.unwrap()) {
    //         Ok(()) => (),
    //         Err(_) => ()
    //     }
    // }

    // if echo_path.exists() {
    //     remove_file(echo_path)?;
    // }

    let feeder_in_sock = UnixDatagram::bind(feeder_in_path)?;
    let feeder_out_sock = UnixDatagram::bind(feeder_out_path)?;
    // let echo_sock = UnixDatagram::bind(echo_path)?;
    let (sender, receiver): (Sender<u8>, Receiver<u8>) = mpsc::channel();

    // before starting threads, set up panic hook to shut down the entire process if a thread panics
    let orig_hook = panic::take_hook();
    panic::set_hook(Box::new(move |panic_info| {
        orig_hook(panic_info);
        process::exit(1);
    }));

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
            panic!("Expected first message from stdin to be an 'init' message, but wasn't");
        }

        // we wait here until the first (init) message is processed so node socket is read and we can connect to it
        receiver.recv().expect("Channel receiver failed to receive");
        feeder_out_sock
            .connect(node_path)
            .expect("Failed to connect feeder out to node socket");

        for line in line_iterator {
            feeder_out_sock.send(line.unwrap().as_bytes()).unwrap();
        }
    });

    let feeder_in_thread_handle = thread::spawn(move || {
        // let echo_sock = UnixDatagram::bind(echo_path).unwrap();
        let mut stdout = stdout().lock();
        let mut buffer = [0; 4096];

        let rec_size = feeder_in_sock.recv(buffer.as_mut_slice()).unwrap();
        stdout
            .write_all(&buffer[0..rec_size])
            .expect("Failed to write received message from socket to stdout");
        stdout
            .write_all(b"\n")
            .expect("Failed to write trailing newline to stdout");
        stdout.flush().unwrap();

        // signal to feeder out thread to continue sending messages after init response has been received
        sender.send(1).expect("Channel sender failed to send");

        loop {
            // let (rec_size, rec_addr) = echo_sock.recv_from(buffer.as_mut_slice()).unwrap();
            // let result = str::from_utf8(&buffer[0..rec_size]).unwrap();
            // let rec_path = rec_addr.as_pathname().unwrap().display();
            // println!("received {rec_size} bytes from {rec_path}");
            // println!("got '{result}' from socket");
            let rec_size = feeder_in_sock.recv(buffer.as_mut_slice()).unwrap();
            stdout
                .write_all(&buffer[0..rec_size])
                .expect("Failed to write received message from socket to stdout");
            stdout
                .write_all(b"\n")
                .expect("Failed to write trailing newline to stdout");
            stdout.flush().unwrap();
        }
    });

    feeder_out_thread_handle.join().unwrap();
    feeder_in_thread_handle.join().unwrap();

    Ok(())
}
