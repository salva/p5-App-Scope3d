#!/usr/bin/perl

use strict;
use warnings;

use Gtk3 '-init';

my $window = Gtk3::Window->new('toplevel');
my $vbox = Gtk3::VBox->new();
$window->add($vbox);
my $hpaned = Gtk3::HPaned->new();
$vbox->add($hpaned);
my $left = Gtk3::Button->new('Left');
$hpaned->add($left);
my $vpaned = Gtk3::VPaned->new();
$hpaned->add($vpaned);
my $up = Gtk3::Button->new('Up');
$vpaned->add($up);
my $down = Gtk3::Button->new('Down');
$vpaned->add($down);
my $button = Gtk3::Button->new('Quit');
$vbox->add($button);
$button->signal_connect(clicked => sub { Gtk3::main_quit });
$window->show_all;
Gtk3::main;
