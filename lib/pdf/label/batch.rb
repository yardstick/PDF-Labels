$: << File.expand_path(File.dirname(__FILE__) + "/../../../vendor")
require 'xml/mapping'
require File.expand_path(File.dirname(__FILE__) + '/glabel_template')
require 'pdf/writer'
#--- require 'breakpoint'

module Pdf
  module Label
    class Batch
      attr_accessor :template, :label, :pdf, :barcode_font, :manual_new_page
      attr_reader :labels_per_page

      @@gt = nil
      def initialize(template_name, pdf_opts = {})
        unless @template = gt.find_template(template_name)
          raise "Template not found!"
        end
        #if the template specifies the paper type, and the user didn't use it.
        if @template.size && !pdf_opts.has_key?(:paper)
          pdf_opts[:paper] = @template.size.gsub(/^.*-/,'')
        end
        #TODO figure out how to cope with multiple label types on a page
        @label = @template.labels["0"]
        #TODO figure out how to handle multiple layouts
        @layout = @label.layouts[0]
        @labels_per_page = @layout.nx * @layout.ny
        @zero_based_labels_per_page = @labels_per_page - 1
        
        @pdf = PDF::Writer.new(pdf_opts)
        @pdf.margins_pt(0, 0, 0, 0)
        
        # Turn off print scaling in the generated PDF to ensure 
        # that the labels are positioned correctly when printing
# TODO This goes boom!        @pdf.viewer_preferences('PrintScaling', '/None')
      end

      def self.load_template_set(template_set_file=nil)
        template_set_file ||= File.expand_path(File.dirname(__FILE__) + "/../../../templates/avery-us-templates.xml")
        @@gt = GlabelsTemplate.load_from_file(template_set_file)
      end

      def self.all_template_names
        gt.find_all_templates
      end

      def self.all_templates
        gt.templates.values
      end
  
      def self.all_barcode_fonts
        {"Code128.afm" => :translation_needed,
         "Code2of5interleaved.afm" => :translation_needed,
         "Code3de9.afm" => :code39,
         "CodeDatamatrix.afm" => :translation_needed,
         "CodeEAN13.afm" => :translation_needed,
         "CodePDF417.afm" => :translation_needed}
      end
  
      def code39(text)
        out = text.upcase
        raise "Characters Not Encodable in Code3of9" unless out.match(/^[0-9A-Z\-\. \/\$\+%\*]+$/)
        out = "*" + out unless out.match(/^\*/)
        out = out + "*" unless out.match(/\*$/)
        return out
      end
  
      def translation_needed(text)
        $stderr.puts("This barcode format does not automatically get formatted yet")
        #TODO - Rob need to add barcode formatting
        return text
      end

=begin rdoc
      add_label takes an argument hash.
      [:position]  Which label slot to print.  Positions are top to bottom, left to right so position 1 is the label in the top lefthand corner.  Defaults to 0
      [:x & :y]  The (x,y) coordinates on the page to print the text.  Ignored if position is specified.
      [:text] What you want to print in the label.  Defaults to the (x,y) of the top left corner of the label.
      [:use_margin] If the label has a markupMargin, setting this argument to true will respect that margin when writing text.  Defaults to true.
      [:justification] Values can be :left, :right, :center, :full.  Defaults to :left
      [:offset_x, offset_y] If your printer doesn't want to print with out margins you can define these values to fine tune printout.
=end
      def add_label(options = {})
        label_x, label_y, label_width = setup_add_label_options(options)

        text = options[:text] || "[#{label_x / 72}, #{label_y / 72}]"
        
        arg_hash = setup_arg_hash(options, label_x, label_y, label_width)

        @pdf.y = label_y
        @pdf.text(text,arg_hash)
      end
  
=begin rdoc
      You can add the same text to many labels this way, takes all the arguments of add_label, but must have position instead of x,y. Requires count.
       [:count] - Number of labels to print
=end
      def add_many_labels(options = {})
        if (options[:x] || options[:y]) && !options[:position]
          raise "Can't use X,Y with add_many_labels, you must use position"
        end
        if !options[:position]
          options[:position] = 0
        end
        raise "Count required" unless options[:count]
        count = options[:count]
        count.times do
          add_label(options)
          options[:position] = options[:position] + 1
        end
      end
=begin rdoc
      To facilitate aligning a printer we give a method that prints the outlines of the labels
=end  
      def do_draw_boxes(write_coord = true, draw_markups = true)
        @layout.nx.times do |x|
          @layout.ny.times do |y|
            box_x, box_y = get_x_y(x, y)
            @pdf.rounded_rectangle(box_x,
                                   box_y,
                                   @label.width.as_pts, 
                                   @label.height.as_pts, 
                                   @label.round.as_pts).stroke
            if write_coord
              text = "#{box_x / 72}, #{box_y / 72}, #{@label.width.number}, #{label.height.number}"
              add_label(:x => box_x, :y => box_y, :text => text)
            end

            if draw_markups
              @label.markupMargins.each do |margin|
                size = margin.size.as_pts
                @pdf.rounded_rectangle(box_x + size,
                                       box_y - margin.size.as_pts,
                                       @label.width.as_pts - 2*size,
                                       @label.height.as_pts - 2*size,
                                       @label.round.as_pts).stroke
              end
              @label.markupLines.each do |line|
                @pdf.line(box_x + line.x1.as_pts,
                          box_y + line.y1.as_pts,
                          box_x + line.x2.as_pts,
                          box_y + line.y2.as_pts).stroke
              end
            end
          end
        end
      end
      
      private :do_draw_boxes

      def draw_boxes(write_coord = true, draw_markups = true)
        pdf.open_object do |heading|
          pdf.save_state
          do_draw_boxes(write_coord, draw_markups)
          pdf.restore_state
          pdf.close_object
          pdf.add_object(heading, :all_pages)
        end
      end
  
=begin rdoc
        add_label takes an argument hash.
        [:position]  Which label slot to print.  Positions are top to bottom, left to right so position 1 is the label in the top lefthand corner.  Defaults to 0
        [:x & :y]  The (x,y) coordinates on the page to print the text.  Ignored if position is specified.
        [:text] What you want to print in the label.  Defaults to the (x,y) of the top left corner of the label.
        [:use_margin] If the label has a markupMargin, setting this argument to true will respect that margin when writing text.  Defaults to true.
        [:justification] Values can be :left, :right, :center, :full.  Defaults to :left
        [:offset_x, offset_y] If your printer doesn't want to print with out margins you can define these values to fine tune printout.
=end
      def add_barcode_label(options = {})
        label_x, label_y, label_width = setup_add_label_options(options)

        text = options[:text] || "[#{label_x / 72}, #{label_y / 72}]"
        
        bar_text = setup_bar_text(options, text)
        
        arg_hash = setup_arg_hash(options, label_x, label_y, label_width)
               
        bar_hash = arg_hash.clone
        bar_hash[:font_size] = options[:bar_size] || 12

        old_font = @pdf.current_font!
        @pdf.select_font(self.barcode_font)

        @pdf.y = label_y
        @pdf.text(bar_text,bar_hash)
  
        @pdf.select_font(old_font)
        # @pdf.text(text,arg_hash)
      end

      def save_as(file_name)
        @pdf.save_as(file_name)
      end
  
      def barcode_font
        @barcode_font ||= "Code3de9.afm"
      end
  
      def barcode_font=(value)
        if Pdf::Label::Batch.all_barcode_fonts.keys.include?(value)
          @barcode_font = value
          return @barcode_font
        else
          raise "Barcode Font Not Found for #{value}"
        end
      end

    protected

=begin rdoc
      Position is top to bottom, left to right, starting at 1 and ending at the end of the page
=end
      def position_to_x_y(position)
        x = (position * 1.0 / @layout.ny).floor
        y = position % @layout.ny
        return get_x_y(x, y)
      end

      def get_x_y(x, y)
        label_y = @pdf.absolute_top_margin
        label_y = label_y + @pdf.top_margin
        label_y = label_y - @layout.y0.as_pts
        label_y = label_y - y * @layout.dy.as_pts

        label_x = @pdf.absolute_left_margin
        label_x = label_x - @pdf.left_margin
        label_x = label_x + @layout.x0.as_pts
        label_x = label_x + x * @layout.dx.as_pts

        return label_x, label_y
      end
      
      def setup_add_label_options(options)
        if position = options[:position]
          # condition to handle multi-page PDF generation. If true, we're past the first page
          if position > @zero_based_labels_per_page
            position = position % @labels_per_page
            # if remainder is zero, we're dealing with the first label of a new page
            @pdf.new_page if position.zero? unless manual_new_page
          end
          label_x, label_y = position_to_x_y(position)
        elsif((label_x = options[:x]) && (label_y = options[:y]))
        else
          label_x, label_y = position_to_x_y(0)
        end
        #line wrap margin
        label_width = label_x + @label.width.as_pts
   
        if (use_margin = options[:use_margin]).nil?
          use_margin = true
        end
        if use_margin
          @label.markupMargins.each {|margin|
            label_x = label_x + margin.size.as_pts
            label_y = label_y - margin.size.as_pts
            label_width = label_width - margin.size.as_pts
          }
        end
    
        if offset = options[:offset_x]
          label_x = label_x + offset
          label_width = label_width + offset
        end
        if offset = options[:offset_y]
          label_y = label_y + offset
        end
        return label_x, label_y, label_width
      end
      
      def setup_arg_hash(options, label_x, label_y, label_width)          
        arg_hash = {:justification => (options[:justification] || :left),
                    :font_size => (options[:font_size] || 12)}

        arg_hash = arg_hash.merge :absolute_left => label_x,
                   :absolute_right => label_width

      end
      
      def setup_bar_text(options, text)
        bar_text = options[:bar_text] || text
        bar_text = send(Pdf::Label::Batch.all_barcode_fonts[self.barcode_font], bar_text)
      end

      def self.gt
        @@gt || self.load_template_set
      end

      def gt
        self.class.gt 
      end
    end
  end
end
