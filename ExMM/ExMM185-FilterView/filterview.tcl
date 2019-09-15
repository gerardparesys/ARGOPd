#!/bin/sh
# This line continues for Tcl, but is a single line for 'sh' \
    exec /usr/bin/wish "$0" -- ${1+"$@"}

# TODO handle changes in samplerate using [block~]

#------------- .mmb edits ----------------
#
# lines 43-47: changed names of coefficient variables (they were
#		incorrect and led to confusion). I updated this
#		throughout (I think).
#
# line 54: added proc mtof for intuitive log frequency scaling.
#
# lines 64-65: converts x axis to midi notes, then frequencies, then
#		radians. Before, the conversion to radians was not
#		done, which is why the response was so jagged proc
#		calc_magnatude_phase: I reworked the math here a pretty good
#		amount. It now gives the correct magnitudes as well as
#		phases. The magnitudes are also converted to dB.
#
# line 134: I added a proc e_alphaq. I just did this to see the
#		response without resonance (q = .7071) to be sure it
#		wasn't what was causing problems. Might be useful
#		later.
#
# lines 146-147: Frequency input for calculating coefficients is a
#                 again log-scaled with mtof.
#
#-----------------------------------------
package require Tk

# global things that are generally useful
set pi [expr acos(-1)]
set 2pi [expr 2.0*$pi]
set LN2 0.69314718
set samplerate 44100

# global variables for all instances
namespace eval filterview:: {
    # array of 'my' instance IDs in a given tkcanvas
    variable mys_in_tkcanvas
    
    # colors
    variable markercolor "#bbbbcc"
    variable selectcolor "blue"
    variable mutedlinecolor "#ffbbbb"
    variable selectedlinecolor "#ff0000"

    # allpass, bandpass, highpass, highshelf, lowpass, lowshelf, notch, peaking, resonant
    variable filters_with_gain [list "highshelf" "lowshelf" "peaking"]
}

#------------------------------------------------------------------------------#
proc filterview::mtof {nn} {
    return [expr pow(2.0, ($nn-45)/12.0)*110.0]
}

proc filterview::drawgraph {my} {
    variable ${my}::tkcanvas
    variable ${my}::tag
    variable ${my}::framex1
    variable ${my}::framey1
    variable ${my}::framex2
    variable ${my}::framey2
    variable ${my}::a1
    variable ${my}::a2
    variable ${my}::b0
    variable ${my}::b1
    variable ${my}::b2

    set framewidth [expr int($framex2 - $framex1)]
    for {set x [expr int($framex1)]} {$x <= $framex2} {incr x 5} {
        lappend magnatudepoints $x
        lappend phasepoints $x
        set nn [expr ($x - $framex1)/$framewidth*120+16.766]
        set result [calc_magnatude_phase \
                        [expr $::2pi * [mtof $nn] / $::samplerate] $a1 $a2 $b0 $b1 $b2 \
                        $framey1 $framey2]
        lappend magnatudepoints [lindex $result 0]
        lappend phasepoints [lindex $result 1]
    }
    $tkcanvas coords responseline$tag $magnatudepoints
    $tkcanvas coords responsefill$tag \
        [concat $magnatudepoints $framex2 $framey2 $framex1 $framey2]
    $tkcanvas coords phaseline$tag $phasepoints
}

proc filterview::update_coefficients {my} {
    variable ${my}::tkcanvas
    variable ${my}::receive_name
    variable ${my}::currentfiltertype
    variable ${my}::filtercenter
    variable ${my}::filterwidth
    variable ${my}::a1
    variable ${my}::a2
    variable ${my}::b0
    variable ${my}::b1
    variable ${my}::b2

    # run the calc for a given filter type first
    $currentfiltertype $my $filtercenter $filterwidth
    # send the result to pd
    pdsend "$receive_name biquad $a1 $a2 $b0 $b1 $b2"
    # update the graph
    drawgraph $my
}

#------------------------------------------------------------------------------#
# calculate magnatude and phase of a given frequency for a set of
# biquad coefficients.  f is input freq in radians
proc filterview::calc_magnatude_phase {f a1 a2 b0 b1 b2 framey1 framey2} {
    set x1 [expr cos(-1.0*$f)]
    set x2 [expr cos(-2.0*$f)]
    set y1 [expr sin(-1.0*$f)]
    set y2 [expr sin(-2.0*$f)]

    set A [expr $b0 + $b1*$x1 + $b2*$x2]
    set B [expr $b1*$y1 + $b2*$y2]
    set C [expr 1 - $a1*$x1 - $a2*$x2]
    set D [expr 0 - $a1*$y1 - $a2*$y2]
    set numermag [expr sqrt($A*$A + $B*$B)]
    set numerarg [expr atan2($B, $A)]
    set denommag [expr sqrt($C*$C + $D*$D)]
    set denomarg [expr atan2($D, $C)]

    set magnatude [expr $numermag/$denommag]
    set phase [expr $numerarg-$denomarg]
    
    set fHz [expr $f * $::samplerate / $::2pi]

    # convert magnitude to dB scale
    set logmagnitude [expr 20.0*log($magnatude)/log(10)]
#    puts stderr "MAGNATUDE at $fHz Hz ($f radians): $magnatude dB: $logmagnitude"
    # clip
    if {$logmagnitude > 25.0} {
        set logmagnitude 25.0
    } elseif {$logmagnitude < -25.0} {
        set logmagnitude -25.0
    }
    # scale to pixel range
    set halfframeheight [expr ($framey2 - $framey1)/2.0]
    set logmagnitude [expr $logmagnitude/25.0 * $halfframeheight]
    # invert and offset
    set logmagnitude [expr -1.0 * $logmagnitude + $halfframeheight + $framey1]

    #	puts stderr "PHASE at $fHz Hz ($f radians): $phase"
    # wrap phase
    if {$phase > $::pi} {
        set phase [expr $phase - $::2pi]
    } elseif {$phase < [expr -$::pi]} {
        set phase [expr $phase + $::2pi]
    }
    # scale phase values to pixels
    set scaledphase [expr $halfframeheight*(-$phase/($::pi)) + $halfframeheight + $framey1]
    
    return [list $logmagnitude $scaledphase]
}

#------------------------------------------------------------------------------#
# calculate coefficients

proc filterview::e_omega {f r} {
    return [expr $::2pi*$f/$r]
}

proc filterview::e_alpha {bw omega} {
    return [expr sin($omega)*sinh($::LN2/2.0 * $bw * $omega/sin($omega))]
}

# just for testing
proc filterview::e_alphaq {q omega} {
    return [expr sin($omega)/(2*$q)]
}

# lowpass
#    f0 = frequency in Hz
#    bw = bandwidth where 1 is an octave
proc filterview::lowpass {my f0pix bwpix} {
    variable ${my}::framex1
    variable ${my}::framex2

    set nn [expr ($f0pix - $framex1)/($framex2-$framex1)*120+16.766]
    set nn2 [expr ($bwpix+$f0pix - $framex1)/($framex2-$framex1)*120+16.766] 
    set f [mtof $nn]
    set bwf [mtof $nn2]
    set bw [expr ($bwf/$f)-1]
#    puts stderr "lowpass: $f $bw $filtercenter $filterwidth"
    set omega [e_omega $f $::samplerate]
    set alpha [e_alpha $bw $omega]
    set b1 [expr 1.0 - cos($omega)]
    set b0 [expr $b1/2.0]
    set b2 $b0
    set a0 [expr 1.0 + $alpha]
    set a1 [expr -2.0*cos($omega)]
    set a2 [expr 1.0 - $alpha]

# get this from ggee/filters
#    if {!check_stability(-a1/a0,-a2/a0,b0/a0,b1/a0,b2/a0)} {
#       post("lowpass: filter unstable -> resetting")]
#        set a0 1; set a1 0; set a2 0
#        set b0 1; set b1 0; set b2 0
#    }

    set ${my}::a1 [expr -$a1/$a0]
    set ${my}::a2 [expr -$a2/$a0]
    set ${my}::b0 [expr $b0/$a0]
    set ${my}::b1 [expr $b1/$a0]
    set ${my}::b2 [expr $b2/$a0]
}

# highpass
proc filterview::highpass {my f0pix bwpix} {
    variable ${my}::framex1
    variable ${my}::framex2

    set nn [expr ($f0pix - $framex1)/($framex2-$framex1)*120+16.766]
    set nn2 [expr ($bwpix+$f0pix - $framex1)/($framex2-$framex1)*120+16.766] 
    set f [mtof $nn]
    set bwf [mtof $nn2]
    set bw [expr ($bwf/$f)-1]
    set omega [e_omega $f $::samplerate]
    set alpha [e_alpha $bw $omega]
    set b1 [expr -1*(1.0 + cos($omega))]
    set b0 [expr -$b1/2.0]
    set b2 $b0
    set a0 [expr 1.0 + $alpha]
    set a1 [expr -2.0*cos($omega)]
    set a2 [expr 1.0 - $alpha]
    
    set ${my}::a1 [expr -$a1/$a0]
    set ${my}::a2 [expr -$a2/$a0]
    set ${my}::b0 [expr $b0/$a0]
    set ${my}::b1 [expr $b1/$a0]
    set ${my}::b2 [expr $b2/$a0]
}

#bandpass
proc filterview::bandpass {my f0pix bwpix} {
    variable ${my}::framex1
    variable ${my}::framex2

    set nn [expr ($f0pix - $framex1)/($framex2-$framex1)*120+16.766]
    set nn2 [expr ($bwpix+$f0pix - $framex1)/($framex2-$framex1)*120+16.766] 
    set f [mtof $nn]
    set bwf [mtof $nn2]
    set bw [expr ($bwf/$f)-1]
    set omega [e_omega $f $::samplerate]
    set alpha [e_alpha $bw $omega]
    set b1 0
    set b0 $alpha
    set b2 [expr -$b0]
    set a0 [expr 1.0 + $alpha]
    set a1 [expr -2.0*cos($omega)]
    set a2 [expr 1.0 - $alpha]
    
    set ${my}::a1 [expr -$a1/$a0]
    set ${my}::a2 [expr -$a2/$a0]
    set ${my}::b0 [expr $b0/$a0]
    set ${my}::b1 [expr $b1/$a0]
    set ${my}::b2 [expr $b2/$a0]
}

#resonant
proc filterview::resonant {my f0pix bwpix} {
    variable ${my}::framex1
    variable ${my}::framex2

    set nn [expr ($f0pix - $framex1)/($framex2-$framex1)*120+16.766]
    set nn2 [expr ($bwpix+$f0pix - $framex1)/($framex2-$framex1)*120+16.766] 
    set f [mtof $nn]
    set bwf [mtof $nn2]
    set bw [expr ($bwf/$f)-1]
    set omega [e_omega $f $::samplerate]
    set alpha [e_alpha $bw $omega]
    set b1 0
    set b0 [expr sin($omega)/2]
    set b2 [expr -$b0]
    set a0 [expr 1.0 + $alpha]
    set a1 [expr -2.0*cos($omega)]
    set a2 [expr 1.0 - $alpha]
    
    set ${my}::a1 [expr -$a1/$a0]
    set ${my}::a2 [expr -$a2/$a0]
    set ${my}::b0 [expr $b0/$a0]
    set ${my}::b1 [expr $b1/$a0]
    set ${my}::b2 [expr $b2/$a0]
}

#notch
proc filterview::notch {my f0pix bwpix} {
    variable ${my}::framex1
    variable ${my}::framex2

    set nn [expr ($f0pix - $framex1)/($framex2-$framex1)*120+16.766]
    set nn2 [expr ($bwpix+$f0pix - $framex1)/($framex2-$framex1)*120+16.766] 
    set f [mtof $nn]
    set bwf [mtof $nn2]
    set bw [expr ($bwf/$f)-1]
    set omega [e_omega $f $::samplerate]
    set alpha [e_alpha $bw $omega]
    set b1 [expr -2.0*cos($omega)]
    set b0 1
    set b2 1
    set a0 [expr 1.0 + $alpha]
    set a1 $b1
    set a2 [expr 1.0 - $alpha]
    
    set ${my}::a1 [expr -$a1/$a0]
    set ${my}::a2 [expr -$a2/$a0]
    set ${my}::b0 [expr $b0/$a0]
    set ${my}::b1 [expr $b1/$a0]
    set ${my}::b2 [expr $b2/$a0]
}

#peaking
proc filterview::peaking {my f0pix bwpix} {
    variable ${my}::framex1
    variable ${my}::framey1
    variable ${my}::framex2
    variable ${my}::framey2
    variable ${my}::filtergain

    set nn [expr ($f0pix - $framex1)/($framex2-$framex1)*120+16.766]
    set nn2 [expr ($bwpix+$f0pix - $framex1)/($framex2-$framex1)*120+16.766] 
    set f [mtof $nn]
    set bwf [mtof $nn2]
    set bw [expr ($bwf/$f)-1]
    set omega [e_omega $f $::samplerate]
    set alpha [e_alpha $bw $omega]
    set amp [expr pow(10.0, (-1.0*(($filtergain)/($framey2-$framey1)*50.0-25.0))/40.0)]
    set alphamulamp [expr $alpha*$amp]
    set alphadivamp [expr $alpha/$amp]
    set b1 [expr -2.0*cos($omega)]
    set b0 [expr 1.0 + $alphamulamp]
    set b2 [expr 1.0 - $alphamulamp]
    set a0 [expr 1.0 + $alphadivamp]
    set a1 $b1
    set a2 [expr 1.0 - $alphadivamp]
    
    set ${my}::a1 [expr -$a1/$a0]
    set ${my}::a2 [expr -$a2/$a0]
    set ${my}::b0 [expr $b0/$a0]
    set ${my}::b1 [expr $b1/$a0]
    set ${my}::b2 [expr $b2/$a0]
}

#lowshelf
proc filterview::lowshelf {my f0pix bwpix} {
    variable ${my}::framex1
    variable ${my}::framey1
    variable ${my}::framex2
    variable ${my}::framey2
    variable ${my}::filtergain

    set nn [expr ($f0pix - $framex1)/($framex2-$framex1)*120+16.766]
    set f [mtof $nn]
    set bw [expr $bwpix / 100.0]
    set amp [expr pow(10.0, (-1.0*(($filtergain)/($framey2-$framey1)*50.0-25.0))/40.0)]
    set omega [e_omega $f $::samplerate]
    set alpha [e_alpha $bw $omega]
    
    set alphamod [expr 2.0*sqrt($amp)*$alpha]
    set cosomega [expr cos($omega)]
    set ampplus [expr $amp+1.0]
    set ampmin [expr $amp-1.0]
    
    
    set b0 [expr $amp*($ampplus - $ampmin*$cosomega + $alphamod)]
    set b1 [expr 2.0*$amp*($ampmin - $ampplus*$cosomega)]
    set b2 [expr $amp*($ampplus - $ampmin*$cosomega - $alphamod)]
    set a0 [expr $ampplus + $ampmin*$cosomega + $alphamod]
    set a1 [expr -2.0*($ampmin + $ampplus*$cosomega)]
    set a2 [expr $ampplus + $ampmin*$cosomega - $alphamod]
    
    set ${my}::a1 [expr -$a1/$a0]
    set ${my}::a2 [expr -$a2/$a0]
    set ${my}::b0 [expr $b0/$a0]
    set ${my}::b1 [expr $b1/$a0]
    set ${my}::b2 [expr $b2/$a0]
}

#highshelf
proc filterview::highshelf {my f0pix bwpix} {
    variable ${my}::framex1
    variable ${my}::framey1
    variable ${my}::framex2
    variable ${my}::framey2
    variable ${my}::filtergain

    set nn [expr ($f0pix - $framex1)/($framex2-$framex1)*120+16.766]
    set nn2 [expr ($bwpix+$f0pix - $framex1)/($framex2-$framex1)*120+16.766] 
    set f [mtof $nn]
    set bwf [mtof $nn2]
    set bw [expr ($bwf/$f)-1]
    set amp [expr pow(10.0, (-1.0*(($filtergain)/($framey2-$framey1)*50.0-25.0))/40.0)]
    set omega [e_omega $f $::samplerate]
    set alpha [e_alpha $bw $omega]
    
    set alphamod [expr 2.0*sqrt($amp)*$alpha]
    set cosomega [expr cos($omega)]
    set ampplus [expr $amp+1.0]
    set ampmin [expr $amp-1.0]
    
    set b0 [expr $amp*($ampplus + $ampmin*$cosomega + $alphamod)]
    set b1 [expr -2.0*$amp*($ampmin + $ampplus*$cosomega)]
    set b2 [expr $amp*($ampplus + $ampmin*$cosomega - $alphamod)]
    set a0 [expr $ampplus - $ampmin*$cosomega + $alphamod]
    set a1 [expr 2.0*($ampmin - $ampplus*$cosomega)]
    set a2 [expr $ampplus - $ampmin*$cosomega - $alphamod]
    
    set ${my}::a1 [expr -$a1/$a0]
    set ${my}::a2 [expr -$a2/$a0]
    set ${my}::b0 [expr $b0/$a0]
    set ${my}::b1 [expr $b1/$a0]
    set ${my}::b2 [expr $b2/$a0]
}

#allpass
proc filterview::allpass {my f0pix bwpix} {
    variable ${my}::framex1
    variable ${my}::framex2

    set nn [expr ($f0pix - $framex1)/($framex2-$framex1)*120+16.766]
    set nn2 [expr ($bwpix+$f0pix - $framex1)/($framex2-$framex1)*120+16.766] 
    set f [mtof $nn]
    set bwf [mtof $nn2]
    set bw [expr ($bwf/$f)-1]
    set omega [e_omega $f $::samplerate]
    set alpha [e_alpha $bw $omega]
    
    set b0 [expr 1.0 - $alpha]
    set b1 [expr -2.0*cos($omega)]
    set b2 [expr 1.0 + $alpha]
    set a0 $b2
    set a1 $b1
    set a2 $b0
    
    set ${my}::a1 [expr -$a1/$a0]
    set ${my}::a2 [expr -$a2/$a0]
    set ${my}::b0 [expr $b0/$a0]
    set ${my}::b1 [expr $b1/$a0]
    set ${my}::b2 [expr $b2/$a0]
}

#------------------------------------------------------------------------------#
# move filter control lines

proc filterview::moveband {my x} {
    variable ${my}::tkcanvas
    variable ${my}::tag
    variable ${my}::previousx
    variable ${my}::framex1
    variable ${my}::framey1
    variable ${my}::framex2
    variable ${my}::framey2
    variable ${my}::filterx1
    variable ${my}::filterx2
    variable ${my}::filterwidth
    variable ${my}::filtercenter

    set dx [expr $x - $previousx]
    set x1 [expr $filterx1 + $dx]
    set x2 [expr $filterx2 + $dx]
    if {$x1 < $framex1} {
        set filterx1 $framex1
        set filterx2 [expr $framex1 + $filterwidth]
    } elseif {$x2 > $framex2} {
        set filterx1 [expr $framex2 - $filterwidth]
        set filterx2 $framex2
    } else {
        set filterx1 $x1
        set filterx2 $x2
    }
    set filterwidth [expr $filterx2 - $filterx1]
    set filtercenter [expr $filterx1 + ($filterwidth/2)]
    $tkcanvas coords bandleft$tag $filterx1 $framey1  $filterx1 $framey2
    $tkcanvas coords bandcenter$tag $filtercenter $framey1  $filtercenter $framey2
    $tkcanvas coords bandright$tag $filterx2 $framey1  $filterx2 $framey2
    set previousx $x
}

proc filterview::movegain {my y} {
    variable ${my}::tkcanvas
    variable ${my}::tag
    variable ${my}::previousy
    variable ${my}::framex1
    variable ${my}::framey1
    variable ${my}::framex2
    variable ${my}::framey2
    variable ${my}::gainy
    variable ${my}::filtergain

    set gain [expr $filtergain + $y - $previousy]
    set framemax [expr $framey2 - $framey1]
    if {[expr $gain < 0]} {
        set filtergain 0
    } elseif {[expr $gain > $framemax]} {
        set filtergain $framemax
    } else {
        set filtergain $gain
    }

    set gainy [expr $framey1 + $filtergain]
    $tkcanvas coords gain$tag $framex1 $gainy $framex2 $gainy
    set previousy $y
}

#------------------------------------------------------------------------------#
# move the filter

proc filterview::start_move {my x y} {
    variable ${my}::tkcanvas
    variable ${my}::tag
    variable ${my}::previousx $x
    variable ${my}::previousy $y
    variable ${my}::framey1
    variable ${my}::framey2
    variable ${my}::filtercenter
    variable selectedlinecolor

    $tkcanvas itemconfigure lines$tag -width 2 -fill $selectedlinecolor
    $tkcanvas bind $tag <Motion> "filterview::move $my %x %y"
    create_centerline $my $framey1 $framey2 $filtercenter
    # cursors are set per toplevel window, not in the tkcanvas
    set mytoplevel [winfo toplevel $tkcanvas]
    $mytoplevel configure -cursor fleur
}

proc filterview::move {my x y} {
    moveband $my $x
    movegain $my $y
    update_coefficients $my
}

#------------------------------------------------------------------------------#
# change the filter

proc filterview::start_changebandwidth {my x y} {
    variable ${my}::tkcanvas
    variable ${my}::tag
    variable ${my}::previousx $x
    variable ${my}::previousy $y
    variable ${my}::framey1
    variable ${my}::framey2
    variable ${my}::filtercenter
    variable ${my}::lessthan_filtercenter

    if {$x < $filtercenter} {
        set lessthan_filtercenter 1
    } else {
        set lessthan_filtercenter 0
    }
    $tkcanvas bind bandedges$tag <Leave> {}
    $tkcanvas bind bandedges$tag <Enter> {}
    $tkcanvas bind bandedges$tag <Motion> {}
    $tkcanvas bind $tag <Motion> "filterview::changebandwidth $my %x %y"
    create_centerline $my $framey1 $framey2 $filtercenter
    # cursors are set per toplevel window, not in the tkcanvas
    set mytoplevel [winfo toplevel $tkcanvas]
    $mytoplevel configure -cursor sb_h_double_arrow
}

proc filterview::changebandwidth {my x y} {
    variable ${my}::tkcanvas
    variable ${my}::tag
    variable ${my}::previousx
    variable ${my}::framex1
    variable ${my}::framey1
    variable ${my}::framex2
    variable ${my}::framey2
    variable ${my}::filterx1
    variable ${my}::filterx2
    variable ${my}::filterwidth
    variable ${my}::filtercenter
    variable ${my}::lessthan_filtercenter

    set dx [expr $x - $previousx]
    if {$lessthan_filtercenter} {
        if {$x < $framex1} {
            set filterx1 $framex1
            set filterx2 [expr $filterx1 + $filterwidth] 
        } elseif {$x < [expr $filtercenter - 75]} {
            set filterx1 [expr $filtercenter - 75]
            set filterx2 [expr $filtercenter + 75]
        } elseif {$x > $filtercenter} {
            set filterx1 $filtercenter
            set filterx2 $filtercenter
        } else {
            set filterx1 $x
            set filterx2 [expr $filterx2 - $dx]
        }
    } else {
        if {$x > $framex2} {
            set filterx2 $framex2
            set filterx1 [expr $filterx2 - $filterwidth] 
        } elseif {$x > [expr $filtercenter + 75]} {
            set filterx1 [expr $filtercenter - 75]
            set filterx2 [expr $filtercenter + 75]
        } elseif {$x < $filtercenter} {
            set filterx1 $filtercenter
            set filterx2 $filtercenter
        } else {
            set filterx2 $x
            set filterx1 [expr $filterx1 - $dx]
        }
    }
    set filterwidth [expr $filterx2 - $filterx1]
    set filtercenter [expr $filterx1 + ($filterwidth/2)]

    $tkcanvas coords bandleft$tag $filterx1 $framey1  $filterx1 $framey2
    $tkcanvas coords bandcenter$tag $filtercenter $framey1  $filtercenter $framey2
    $tkcanvas coords bandright$tag $filterx2 $framey1  $filterx2 $framey2
    set previousx $x

    movegain $my $y
    update_coefficients $my
}

proc filterview::band_cursor {my x} {
    variable ${my}::tkcanvas
    variable ${my}::filtercenter
    # cursors are set per toplevel window, not in the tkcanvas
    set mytoplevel [winfo toplevel $tkcanvas]
    if {$x < $filtercenter} {
        $mytoplevel configure -cursor left_side
    } else {
        $mytoplevel configure -cursor right_side
    }
}

proc filterview::enterband {my} {
    variable ${my}::tkcanvas
    variable ${my}::tag
    variable selectedlinecolor
    $tkcanvas bind $tag <ButtonPress-1> {}
    $tkcanvas bind bandedges$tag <Motion> "filterview::band_cursor $my %x"
    $tkcanvas itemconfigure band$tag -width 2 -fill $selectedlinecolor
}

proc filterview::leaveband {my} {
    variable ${my}::tkcanvas
    variable ${my}::tag
    variable mutedlinecolor
    $tkcanvas bind $tag <ButtonPress-1> "filterview::start_move $my %x %y"
    $tkcanvas bind bandedges$tag <Motion> {}
    $tkcanvas itemconfigure band$tag -width 1 -fill $mutedlinecolor
    # cursors are set per toplevel window, not in the tkcanvas
    set mytoplevel [winfo toplevel $tkcanvas]
    $mytoplevel configure -cursor $::cursor_runmode_nothing
}

#------------------------------------------------------------------------------#

proc filterview::create_centerline {my y1 y2 centery} {
    variable ${my}::tkcanvas
    variable ${my}::tag
    variable mutedlinecolor
    # bandwidth box center
    $tkcanvas create line $centery $y1 $centery $y2 \
        -fill $mutedlinecolor \
        -tags [list $tag lines$tag band$tag bandcenter$tag]
}

proc filterview::delete_centerline {my} {
    variable ${my}::tkcanvas
    variable ${my}::tag
    $tkcanvas delete bandcenter$tag
}

#------------------------------------------------------------------------------#

# Tcl doesn't get the frame location from Pd in filterview, so we
# measure the current frame location and reset the frame x/y variables.
proc filterview::reset_frame_location {my} {
    variable ${my}::tkcanvas
    variable ${my}::tag
    set coordslist [$tkcanvas coords frame$tag]
    if {[llength $coordslist] == 4} {
        variable ${my}::framex1 [lindex $coordslist 0]
        variable ${my}::framey1 [lindex $coordslist 1]
        variable ${my}::framex2 [lindex $coordslist 2]
        variable ${my}::framey2 [lindex $coordslist 3]
    }
}

proc filterview::stop_editing {my} {
    variable ${my}::tkcanvas
    variable ${my}::tag
    variable mutedlinecolor
    $tkcanvas bind $tag <Motion> {}
    $tkcanvas itemconfigure lines$tag -width 1 -fill $mutedlinecolor
    $tkcanvas bind bandedges$tag <Enter> "filterview::enterband $my"
    $tkcanvas bind bandedges$tag <Leave> "filterview::leaveband $my"
    delete_centerline $my
    # cursors are set per toplevel window, not in the tkcanvas
    set mytoplevel [winfo toplevel $tkcanvas]
    $mytoplevel configure -cursor $::cursor_runmode_nothing
}

proc filterview::set_for_editmode {mytoplevel} {
    variable mys_in_tkcanvas
    set tkcanvas [tkcanvas_name $mytoplevel]
    if {$::editmode($mytoplevel) == 1} {
        # disable the graph interaction while editing
        if {[array names mys_in_tkcanvas -exact $tkcanvas] eq $tkcanvas} {
            foreach my $mys_in_tkcanvas($tkcanvas) {
                variable ${my}::tag
                $tkcanvas bind $tag <ButtonPress-1> {}
                $tkcanvas bind $tag <ButtonRelease-1> {}
                $tkcanvas bind bandedges$tag <ButtonPress-1> {}
                $tkcanvas bind bandedges$tag <ButtonRelease-1> {}
                $tkcanvas bind bandedges$tag <Enter> {}
                $tkcanvas bind bandedges$tag <Leave> {}
            }
        }
    } else {
        if {[array names mys_in_tkcanvas -exact $tkcanvas] eq $tkcanvas} {
            foreach my $mys_in_tkcanvas($tkcanvas) {
                variable ${my}::tag
                $tkcanvas bind $tag <ButtonPress-1> \
                    "filterview::start_move $my %x %y"
                $tkcanvas bind $tag <ButtonRelease-1> \
                    "filterview::stop_editing $my"
                $tkcanvas bind bandedges$tag <ButtonPress-1> \
                    "filterview::start_changebandwidth $my %x %y"
                $tkcanvas bind bandedges$tag <ButtonRelease-1> \
                    "filterview::stop_editing $my"
                reset_frame_location $my
            }
        }
    }
}

#------------------------------------------------------------------------------#

# sets up an new instance of the class
proc filterview::new {my canvas rname t x1 y1 x2 y2} {
    namespace eval $my {
        # init all here to make sure they are not blank
        variable tag "tag"                   ;# unique ID for canvas elements
        variable tkcanvas ".tkcanvas"        ;# Tk canvas this is drawn on
        variable receive_name "receive_name" ;# Pd name to send callbacks to

        variable currentfiltertype "peaking"

        variable previousx 0
        variable previousy 0

        variable filtergain 100 ;# the unit is pixels, 0-200, 100 means no gain

        # coefficients for [biquad~]
        variable a1 0
        variable a2 0
        variable b0 1
        variable b1 0
        variable b2 0
    }

    variable ${my}::receive_name $rname
    variable ${my}::tag $t

    update $my $canvas $x1 $y1 $x2 $y2
}

# updates an existing instance when its about to be drawn again
proc filterview::update {my canvas x1 y1 x2 y2} {
    variable ${my}::tkcanvas $canvas
    variable ${my}::filtergain

    # convert these all to floats so the math works properly
    variable ${my}::framex1 [expr $x1 * 1.0]
    variable ${my}::framey1 [expr $y1 * 1.0]
    variable ${my}::framex2 [expr $x2 * 1.0]
    variable ${my}::framey2 [expr $y2 * 1.0]

    variable ${my}::midpoint [expr (($framey2 - $framey1) / 2) + $framey1]
    variable ${my}::hzperpixel [expr 20000.0 / ($framex2 - $framex1)]
    variable ${my}::magnatudeperpixel [expr 0.5 / ($framey2 - $framey1)]

    variable ${my}::gainy [expr $framey1 + $filtergain]
    # TODO make these set by something else, saved state?
    variable ${my}::filterx1 [expr $framex1 + 120.0]
    variable ${my}::filterx2 [expr $framex1 + 180.0]

    variable ${my}::filterwidth [expr $filterx2 - $filterx1]
    variable ${my}::filtercenter [expr $filterx1 + ($filterwidth/2)]
}

proc filterview::eraseme {my} {
    variable ${my}::tkcanvas
    variable ${my}::tag
    variable mys_in_tkcanvas
    $tkcanvas delete $tag
    set mys_in_tkcanvas($tkcanvas) \
        [lsearch -all -inline -not -exact $mys_in_tkcanvas($tkcanvas) $my]
}

proc filterview::setfiltertype {my filtertype} {
    variable ${my}::tkcanvas
    variable ${my}::tag
    variable ${my}::currentfiltertype $filtertype
    variable ${my}::framex1
    variable ${my}::framex2
    variable ${my}::gainy
    variable filters_with_gain
    variable mutedlinecolor

    variable ${my}::framey1
    variable ${my}::framey2

    if {[lsearch -exact $filters_with_gain $filtertype] > -1} {
        # if any gain lines exist from before, delete first
        $tkcanvas delete gain$tag
        $tkcanvas create line $framex1 $gainy $framex2 $gainy \
            -fill $mutedlinecolor \
            -tags [list $tag lines$tag gain$tag]
    } else {
        $tkcanvas delete gain$tag
    }
    update_coefficients $my
}

proc filterview::drawme {my canvas name t x1 y1 x2 y2 filtertype} {
    # if the $my namespace already exists, that means we already
    # have an instance active and setup.
    if {[namespace exists $my]} {
        update $my $canvas $x1 $y1 $x2 $y2
    } else {
        new $my $canvas $name $t $x1 $y1 $x2 $y2
    }
    variable ${my}::tkcanvas
    variable ${my}::receive_name
    variable ${my}::tag
    variable ${my}::framex1
    variable ${my}::framey1
    variable ${my}::framex2
    variable ${my}::framey2
    variable ${my}::filterx1
    variable ${my}::filterx2
    variable ${my}::midpoint
    variable mys_in_tkcanvas
    variable markercolor
    variable mutedlinecolor

    # background
    $tkcanvas create rectangle $framex1 $framey1 $framex2 $framey2 \
        -outline $markercolor -fill "#f8feff" \
        -tags [list $tag frame$tag]

    # magnatude response graph fill
    $tkcanvas create polygon $framex1 $midpoint $framex2 $midpoint \
        $framex2 $framey2 $framex1 $framey2 \
        -fill "#e7f6d8" \
        -tags [list $tag response$tag responsefill$tag]

    # magnatude response graph line
    $tkcanvas create line $framex1 $midpoint $framex2 $midpoint \
        -fill "#B7C6A8" -width 3 \
        -tags [list $tag response$tag responseline$tag]

    # zero line/equator
    $tkcanvas create line $framex1 $midpoint $framex2 $midpoint \
        -fill $markercolor \
        -tags [list $tag zeroline$tag]

    # phase response graph line
    $tkcanvas create line $framex1 $midpoint $framex2 $midpoint \
        -fill "#ccf" -width 1 \
        -tags [list $tag response$tag phaseline$tag]

    # bandwidth box left side
    $tkcanvas create line $filterx1 $framey1 $filterx1 $framey2 \
        -fill $mutedlinecolor \
        -tags [list $tag lines$tag band$tag bandleft$tag bandedges$tag]
    # bandwidth box right side
    $tkcanvas create line $filterx2 $framey1 $filterx2 $framey2 \
        -fill $mutedlinecolor \
        -tags [list $tag lines$tag band$tag bandright$tag bandedges$tag]

    # inlet/outlet
    set nletx [expr $framex1 + 7]
    set inlety [expr $framey1 + 2]
    set outletx [expr $framex2 - 7]
    set outlety [expr $framey2 - 2]
    #inlet0
    $tkcanvas create line $framex1 $framey1 $nletx $framey1 \
        $nletx $inlety $framex1 $inlety $framex1 $framey1 \
        -tags [list $tag nlet$tag]
    #outlet0
    $tkcanvas create line $framex1 $framey2 $nletx $framey2 \
        $nletx $outlety $framex1 $outlety $framex1 $framey1 \
        -tags [list $tag nlet$tag]
    #outlet1
    $tkcanvas create line $outletx $framey2 $framex2 $framey2 \
        $framex2 $outlety $outletx $outlety $outletx $framey2 \
        -tags [list $tag nlet$tag]

    setfiltertype $my $filtertype

    # run to set things up
    stop_editing $my
    lappend mys_in_tkcanvas($tkcanvas) $my
    set_for_editmode [winfo toplevel $tkcanvas]
}

proc filterview::select {my state} {
    variable ${my}::tkcanvas
    variable ${my}::tag
    variable selectcolor
    variable markercolor
    if {$state} {
        $tkcanvas itemconfigure frame$tag -outline $selectcolor -width 2
     } else {
        $tkcanvas itemconfigure frame$tag -outline $markercolor -width 1
     }
}

# sets the biquad coefficients from a list in the first inlet
proc filterview::coefficients {my aa1 aa2 bb0 bb1 bb2} {
    variable ${my}::a1 $aa1
    variable ${my}::a2 $aa2
    variable ${my}::b0 $bb0
    variable ${my}::b1 $bb1
    variable ${my}::b2 $bb2
    drawgraph $my
}

# sets up the class
proc filterview::setup {} {
    bind PatchWindow <<EditMode>> {+filterview::set_for_editmode %W}    
    # check if we are Pd < 0.43, which has no 'pdsend', but a 'pd' coded in C
    if {[llength [info procs ::pdsend]] == 0} {
        proc ::pdsend {args} {pd "[join $args { }] ;"}
    }

    # if not loading within Pd, then create a window and canvas to work with
    if {[llength [info procs ::pdtk_post]] == 0} {
        set my ::FAKEDMY
        set mytoplevel .
        set tkcanvas .c
        set tag FAKEDTAG
        catch {console show}
        puts stderr "setting up as standalone dev mode!"

        # this stuff creates a dev skeleton
        set ::cursor_runmode_nothing arrow
        array set ::editmode [list $mytoplevel 0]
        array set filterview::mys_in_tkcanvas [list $tkcanvas $my]
        proc ::pdtk_post {args} {puts stderr "pdtk_post $args"}
        proc ::pdsend {args} {puts stderr "pdsend $args"}
        proc ::tkcanvas_name {mytoplevel} "return $tkcanvas"

        wm geometry . 400x400+500+40
        canvas $tkcanvas
        pack $tkcanvas -side left -expand 1 -fill both
        filterview::drawme $my $tkcanvas FAKE_RECEIVE_NAME $tag 30.0 30.0 330.0 230.0 "peaking"
        filterview::set_for_editmode .
    }
}

filterview::setup
