# frozen_string_literal: true

require 'csv'

class Admin::WatchedWordsController < Admin::AdminController
  skip_before_action :check_xhr, only: [:download]

  def index
    render_json_dump WatchedWordListSerializer.new(WatchedWord.by_action, scope: guardian, root: false)
  end

  def create
    watched_word = WatchedWord.create_or_update_word(watched_words_params)
    if watched_word.valid?
      render json: watched_word, root: false
    else
      render_json_error(watched_word)
    end
  end

  def destroy
    watched_word = WatchedWord.find_by(id: params[:id])
    raise Discourse::InvalidParameters.new(:id) unless watched_word
    watched_word.destroy!
    render json: success_json
  end

  def upload
    file = params[:file] || params[:files].first
    action_key = params[:action_key].to_sym
    has_replacement = WatchedWord.has_replacement?(action_key)

    Scheduler::Defer.later("Upload watched words") do
      begin
        CSV.foreach(file.tempfile, encoding: "bom|utf-8") do |row|
          if row[0].present? && (!has_replacement || row[1].present?)
            WatchedWord.create_or_update_word(
              word: row[0],
              replacement: has_replacement ? row[1] : nil,
              action_key: action_key
            )
          end
        end

        data = { url: '/ok' }
      rescue => e
        data = failed_json.merge(errors: [e.message])
      end
      MessageBus.publish("/uploads/txt", data.as_json, client_ids: [params[:client_id]])
    end

    render json: success_json
  end

  def download
    params.require(:id)
    name = watched_words_params[:id].to_sym
    action = WatchedWord.actions[name]
    raise Discourse::NotFound if !action

    content = WatchedWord.where(action: action)
    if WatchedWord.has_replacement?(name)
      content = content.pluck(:word, :replacement).map(&:to_csv).join
    else
      content = content.pluck(:word).join("\n")
    end

    headers['Content-Length'] = content.bytesize.to_s
    send_data content,
      filename: "#{Discourse.current_hostname}-watched-words-#{name}.csv",
      content_type: "text/csv"
  end

  def clear_all
    params.require(:id)
    name = watched_words_params[:id].to_sym
    action = WatchedWord.actions[name]
    raise Discourse::NotFound if !action

    WatchedWord.where(action: action).delete_all
    WordWatcher.clear_cache!
    render json: success_json
  end

  private

  def watched_words_params
    params.permit(:id, :word, :replacement, :action_key)
  end

end
