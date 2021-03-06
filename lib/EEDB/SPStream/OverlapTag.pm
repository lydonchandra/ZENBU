=head1 NAME - EEDB::SPStream::OverlapTag

=head1 DESCRIPTION

a signal-processing-stream "metadata tager" built around the same overlap code as 
EEDB::Tools:OverlapCompare and EEDB::SPStream::OverlapFilter.  
The side-stream is used to overlap with the primary
stream.  If a feature/expression on the primary stream overlaps with a feature on 
the side stream, the feature_source of the side-feature is added to the metadata
as a tag "overlaptag::<feature-source-name>".

=head1 CONTACT

Jessica Severin <severin@gsc.riken.jp>

=head1 LICENSE

 * Software License Agreement (BSD License)
 * EdgeExpressDB [eeDB] system
 * copyright (c) 2007-2009 Jessica Severin RIKEN OSC
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of Jessica Severin RIKEN OSC nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ''AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are usually preceded with a _

=cut

package EEDB::SPStream::OverlapTag;

use strict;

use EEDB::SPStream;
our @ISA = qw(EEDB::SPStream);

#################################################
# Class methods
#################################################

sub class { return "EEDB::SPStream::OverlapTag"; }


#################################################
# 
# initialization and configuration methods
#
#################################################

sub init {
  my $self = shift;
  my @args = @_;
  $self->SUPER::init(@args);

  $self->{'current_chrom_name'}= undef;
  $self->{'current_stream'}= undef;
  $self->{'feature_buffer'}= [];
  $self->{'ignore_strand'} = 0;

  $self->{'debug'} = 0;
  
  return $self;
}


=head2 side_stream

  Description: set the input or source stream feeding objects into this level of the stream stack.
  Returntype : either an MQdb::DBStream or subclass of EEDB::SPStream object or undef if not set
  Exceptions : none 

=cut

sub side_stream {
  my $self = shift;
  if(@_) {
    my $stream = shift;
    unless(defined($stream) && ($stream->isa('EEDB::SPStream') or $stream->isa('MQdb::DBStream'))) {
      die("ERROR:: side_stream() param must be a EEDB::SPStream or MQdb::DBStream");
    }
    if($stream eq $self) {
      die("ERROR: can not set source_stream() to itself");
    }
    $self->{'_side_stream'} = $stream;
  }
  return $self->{'_side_stream'};
}

sub ignore_strand {
  my $self = shift;
  return $self->{'ignore_strand'} = shift if(@_);
  return $self->{'ignore_strand'};
}


#################################################
#
# override method for subclasses which will
# do all the work
#
#################################################

sub next_in_stream {
  my $self = shift;
  if(!defined($self->source_stream)) { return undef; }
  my $feature = $self->source_stream->next_in_stream;
  if($feature) {
    $self->process_feature($feature);
    return $feature;
  } 
  return undef;
}

#
#################################################
#

sub display_desc {
  my $self = shift;
  my $str = sprintf("OverlapTag");
  return $str;
}

sub xml_start {
  my $self = shift;
  my $str = "<spstream module=\"OverlapTag\" >";
  $str .= sprintf("<ignore_strand value=\"%f\"/>", $self->ignore_strand); 
  $str .= "  <side_stream>\n";
  $str .= $self->side_stream->xml;
  $str .= "  </side_stream>\n";
  
  return $str;
}


###############################################################
#
# The OverlapCompare algorithm code modified for 
# stream-filtering without the call-out functions
#
###############################################################

sub process_feature {
  my $self = shift;
  my $feature1 = shift;
  
  return undef unless($feature1->chrom);

  if(!defined($self->{'current_chrom_name'}) or ($feature1->chrom_name ne $self->{'current_chrom_name'})) {
    #change the chrom and stream
    
    my $stream2 = $self->side_stream->stream_by_named_region($feature1->chrom->assembly->ucsc_name, $feature1->chrom_name, undef, undef);
  
    $self->{'current_chrom_name'}= $feature1->chrom_name;
    $self->{'current_stream'}= $stream2;

    #
    # to setup buffer, scan into stream2 until we get to around $feature1
    #
    my $feature2a = $stream2->next_in_stream;
    my $feature2b = $stream2->next_in_stream;

    while($self->overlap_check($feature1, $feature2b) == 1) {
      #F1 is past the end of the buffer so move the buffer forward (f1>f2)
      $feature2a = $feature2b;
      $feature2b = $stream2->next_in_stream;
    }
    $self->{'f2_buffer'}= [$feature2a, $feature2b];
  }

  my $f2_buffer = $self->{'f2_buffer'};
  my $stream2   = $self->{'current_stream'};
 
  #
  # first do work on the end of the buffer, in order to properly capture 'betweeen' events we 
  # need to make sure buffer goes beyond the current $feature1
  #
  my $feature2  = undef;
  if(@$f2_buffer) { $feature2 = $f2_buffer->[scalar(@$f2_buffer)-1]; }
  while($feature2 and ($self->overlap_check($feature1, $feature2) != -1)) {
    $feature2 = $stream2->next_in_stream;
    if($feature2) { push @$f2_buffer, $feature2; }
  }

  #
  # then do work on the head of the buffer
  #
  my $feature2a = $f2_buffer->[0];
  my $feature2b = $f2_buffer->[1];
  while($feature2b and ($self->overlap_check($feature1, $feature2b) == 1)) {
    #F1 past is past both f2a and f2b so trim the head
    shift @$f2_buffer;
    $feature2a = $feature2b;
    $feature2b = $f2_buffer->[1];
  }

  my $does_overlap = undef;
  foreach $feature2 (@$f2_buffer) {
    next unless(defined($feature2));
    if($self->overlap_check($feature1, $feature2) == 0) {
      #since this is a filter, any overlap is good enough
      if($self->ignore_strand or ($feature1->strand eq $feature2->strand)) { 
        # do the tagging here.
        $feature1->temp_metadataset->add_tag_symbol("overlaptag", $feature2->feature_source->category);
      }
      if(!$self->ignore_strand and ($feature1->strand ne $feature2->strand)) {
        $feature1->temp_metadataset->add_tag_symbol("overlaptag", "antisense");
      }
    }
  }
  $feature1->temp_metadataset->remove_duplicates;
  return $feature1;
}


sub overlap_check {
  my $self = shift;
  my $feature1 = shift;
  my $feature2 = shift;

  return -999 unless($feature1 and $feature2); #stop
  
  # -1 means feature2 stream has not caught up to feature1 yet
  #  1 means feature2 stream has gone past feature1
  #  0 means overlapping
  
  my $mod_start = $feature2->chrom_start;
  my $mod_end   = $feature2->chrom_end;
  
  if($feature1->chrom_start > $mod_end)   { return  1; } #f1 starts AFTER f2 ends   (f1>f2)
  if($feature1->chrom_end   < $mod_start) { return  -1; } #f1 ends before f2 starts (f1<g2)
  
  if(($mod_start <= $feature1->chrom_end) and
     ($mod_end   >= $feature1->chrom_start)) { 
    return 0;
  }
  return -999;  #hmm something is off
}


1;

